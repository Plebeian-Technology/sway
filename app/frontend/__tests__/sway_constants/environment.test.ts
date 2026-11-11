import { beforeEach, describe, expect, it, vi } from "vitest";

// @lat: [[frontend-env-flags-build-mode#Why the frontend env flags read build mode, not hostname]]

const setHostname = (hostname: string) => {
    Object.defineProperty(window, "location", {
        value: Object.assign({}, window.location, { hostname }),
        writable: true,
        configurable: true,
    });
};

describe("environment constants", () => {
    beforeEach(() => {
        vi.resetModules();
    });

    it.each(["localhost", "dev.example.test", "sway-dev.example.com", "app.sway.vote"])(
        "reports a non-production bundle as development when served from %s",
        async (hostname) => {
            setHostname(hostname);

            const { IS_DEVELOPMENT, IS_NOT_PRODUCTION, IS_PRODUCTION } = await import("app/frontend/sway_constants");

            expect(IS_DEVELOPMENT).toBe(true);
            expect(IS_NOT_PRODUCTION).toBe(true);
            expect(IS_PRODUCTION).toBe(false);
        },
    );

    it("keeps IS_DEVELOPMENT and IS_PRODUCTION mutually exclusive", async () => {
        const { IS_DEVELOPMENT, IS_PRODUCTION } = await import("app/frontend/sway_constants");

        expect(IS_DEVELOPMENT).toBe(!IS_PRODUCTION);
    });
});
