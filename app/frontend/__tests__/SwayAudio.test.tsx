import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "@testing-library/react";
import { installLocalStorage, removeLocalStorage } from "app/frontend/__tests__/__mocks__/local_storage";

const sentry = vi.hoisted(() => ({ captureMessage: vi.fn<(message: string, level?: string) => void>() }));
vi.mock("@sentry/react", () => ({ captureMessage: sentry.captureMessage }));

// @lat: [[frontend-test-infrastructure-notes#SwayAudio: resetting the module registry]]
const renderWithBucket = async (bucket: string | undefined, filePath: string) => {
    vi.resetModules();
    if (bucket === undefined) {
        vi.stubEnv("VITE_SWAY_ASSETS_BUCKET", "");
    } else {
        vi.stubEnv("VITE_SWAY_ASSETS_BUCKET", bucket);
    }
    const { default: SwayAudio } = await import("app/frontend/components/SwayAudio");
    return render(<SwayAudio filePath={filePath} />);
};

describe("SwayAudio", () => {
    beforeEach(() => {
        sentry.captureMessage.mockClear();
        // reportOnce also remembers in storage. This jsdom window has none, so
        // install a fresh one per example — otherwise the first report would be
        // the only one any example ever sees.
        installLocalStorage();
    });

    afterEach(() => {
        vi.unstubAllEnvs();
        removeLocalStorage();
    });

    it("joins a plain file name to the bucket it was built with", async () => {
        const { container } = await renderWithBucket("test-bucket", "summary.mp3");

        expect(container.querySelector("audio")).toHaveAttribute(
            "src",
            "https://storage.googleapis.com/test-bucket/summary.mp3",
        );
    });

    it("leaves a path that already carries its own address alone", async () => {
        const { container } = await renderWithBucket("test-bucket", "https://example.com/a.mp3");

        expect(container.querySelector("audio")).toHaveAttribute("src", "https://example.com/a.mp3");
    });

    it("shows no player when there is no bucket and the path needs one", async () => {
        const { container } = await renderWithBucket(undefined, "summary.mp3");

        expect(container.querySelector("audio")).toBeNull();
    });

    it("still plays a full address when there is no bucket", async () => {
        const { container } = await renderWithBucket(undefined, "https://example.com/a.mp3");

        expect(container.querySelector("audio")).toHaveAttribute("src", "https://example.com/a.mp3");
    });

    it("tells Sentry when a player needed a bucket and there was none", async () => {
        await renderWithBucket(undefined, "summary.mp3");

        expect(sentry.captureMessage).toHaveBeenCalledWith(
            expect.stringContaining("VITE_SWAY_ASSETS_BUCKET"),
            expect.objectContaining({ level: "error" }),
        );
    });

    it("says nothing to Sentry when the bucket is there", async () => {
        await renderWithBucket("test-bucket", "summary.mp3");

        expect(sentry.captureMessage).not.toHaveBeenCalled();
    });

    it("says nothing to Sentry for a path that never needed a bucket", async () => {
        await renderWithBucket(undefined, "https://example.com/a.mp3");

        expect(sentry.captureMessage).not.toHaveBeenCalled();
    });
});
