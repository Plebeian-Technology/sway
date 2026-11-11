import { describe, expect, it, vi } from "vitest";
import { sentryVitePlugin } from "@sentry/vite-plugin";
import type { Plugin } from "vite";
import { retryingSourceMapUpload } from "../../../vite/retryingSourceMapUpload";

// @lat: [[sentry-sourcemap-upload-delete-guard#Why the source-map upload retries on failure]]

const pluginWithUpload = (writeBundle: () => unknown): Plugin =>
    ({ name: "test-plugin", writeBundle }) as unknown as Plugin;

// Call the wrapped hook the way Vite calls it.
const runUpload = async (plugin: Plugin): Promise<unknown> => {
    const hook = plugin.writeBundle;
    if (typeof hook !== "function") {
        throw new Error("the wrapper did not leave writeBundle as a function");
    }
    return (hook as () => unknown).call(plugin);
};

describe("retryingSourceMapUpload", () => {
    it("does not retry an upload that works first time", async () => {
        const upload = vi.fn<() => string>(() => "uploaded");
        const wrapped = retryingSourceMapUpload(pluginWithUpload(upload), { waitMs: 0 });

        await expect(runUpload(wrapped)).resolves.toBe("uploaded");
        expect(upload).toHaveBeenCalledTimes(1);
    });

    it("tries again after a failure and reports success", async () => {
        const upload = vi
            .fn<() => Promise<string>>()
            .mockRejectedValueOnce(new Error("Could not resolve host: us.sentry.io"))
            .mockResolvedValueOnce("uploaded");
        const wrapped = retryingSourceMapUpload(pluginWithUpload(upload), {
            waitMs: 0,
            warn: () => {},
        });

        await expect(runUpload(wrapped)).resolves.toBe("uploaded");
        expect(upload).toHaveBeenCalledTimes(2);
    });

    // The whole point of the rule this sits inside: an upload that really is
    // broken must still stop the build, so the image never deletes maps it
    // failed to send.
    it("still fails the build when every attempt fails", async () => {
        const failure = new Error("Could not resolve host: us.sentry.io");
        const upload = vi.fn<() => Promise<string>>().mockRejectedValue(failure);
        const wrapped = retryingSourceMapUpload(pluginWithUpload(upload), {
            attempts: 3,
            waitMs: 0,
            warn: () => {},
        });

        await expect(runUpload(wrapped)).rejects.toThrow("Could not resolve host");
        expect(upload).toHaveBeenCalledTimes(3);
    });

    it("rethrows the original failure, not one of its own", async () => {
        const failure = new Error("the real reason");
        const wrapped = retryingSourceMapUpload(pluginWithUpload(vi.fn().mockRejectedValue(failure)), {
            attempts: 2,
            waitMs: 0,
            warn: () => {},
        });

        await expect(runUpload(wrapped)).rejects.toBe(failure);
    });

    it("says something between attempts, so a retry is never silent", async () => {
        const warn = vi.fn<(msg: string) => void>();
        const wrapped = retryingSourceMapUpload(pluginWithUpload(vi.fn().mockRejectedValue(new Error("nope"))), {
            attempts: 3,
            waitMs: 0,
            warn,
        });

        await expect(runUpload(wrapped)).rejects.toThrow("nope");
        expect(warn).toHaveBeenCalledTimes(2);
        expect(warn.mock.calls[0]?.[0]).toContain("attempt 1 of 3");
    });

    it("leaves a plugin with no writeBundle hook alone", () => {
        const plugin = { name: "no-upload-here" } as Plugin;

        expect(retryingSourceMapUpload(plugin)).toBe(plugin);
    });
});

describe("the Sentry plugin shape the wrapper depends on", () => {
    // Read as Vite plugins on purpose. The plugin's own published type does not
    // declare writeBundle at all, so TypeScript cannot answer the question these
    // two examples ask — only the running code can.
    const plugins = [
        sentryVitePlugin({
            authToken: "not-a-real-token",
            org: "sway-a6",
            project: "sway",
        }),
    ].flat() as unknown as Plugin[];

    it("still uploads from a writeBundle hook that is a plain function", () => {
        const uploaders = plugins.filter((plugin) => typeof plugin?.writeBundle === "function");

        expect(uploaders.length).toBeGreaterThan(0);
    });

    it("still names the plugin the wrapper is applied to", () => {
        expect(plugins.map((plugin) => plugin?.name)).toContain("sentry-vite-plugin");
    });
});
