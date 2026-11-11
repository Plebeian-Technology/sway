import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// @lat: [[frontend-test-infrastructure-notes#Warming a module transform out of a test's own budget]]
await import("app/frontend/sway_utils/offlineTelemetry");

// @lat: [[offline-telemetry#Why offline events never leave the browser]]
describe("trackOfflineEvent", () => {
    let originalFetch: typeof globalThis.fetch;
    const sendBeacon = vi.fn<(url: string, data: BodyInit) => boolean>().mockReturnValue(true);
    const fetchSpy = vi.fn<typeof globalThis.fetch>();

    beforeEach(() => {
        vi.clearAllMocks();
        vi.resetModules();
        originalFetch = globalThis.fetch;
        // Both sinks are present and working, so a call to either is a real
        // regression rather than a missing global.
        globalThis.fetch = fetchSpy as unknown as typeof globalThis.fetch;
        Object.defineProperty(navigator, "sendBeacon", {
            value: sendBeacon,
            configurable: true,
            writable: true,
        });
    });

    afterEach(() => {
        globalThis.fetch = originalFetch;
        vi.clearAllMocks();
    });

    it("sends nothing over the network, for any event name", async () => {
        const { trackOfflineEvent } = await import("app/frontend/sway_utils/offlineTelemetry");

        trackOfflineEvent("offline_session_started", { isOnline: false });
        trackOfflineEvent("offline_vote_attempt_blocked");
        trackOfflineEvent("sw_update_prompt_shown");
        trackOfflineEvent("sw_update_prompt_accepted");

        expect(sendBeacon).not.toHaveBeenCalled();
        expect(fetchSpy).not.toHaveBeenCalled();
    });

    it("never throws, so measuring the app cannot break the app", async () => {
        const { trackOfflineEvent } = await import("app/frontend/sway_utils/offlineTelemetry");

        expect(() => trackOfflineEvent("offline_session_started")).not.toThrow();
    });
});
