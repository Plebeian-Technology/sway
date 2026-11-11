// @lat: [[registration-funnel-telemetry#Client-side telemetry dispatch and step mapping]]
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
    captureReferralAttribution,
    getAttributionKey,
    getOrCreateVisitorToken,
    hasStepBeenRecordedInSession,
    markStepRecordedInSession,
    trackFunnelStep,
    trackFunnelStepOnce,
} from "app/frontend/sway_utils/funnelTracker";
import { SWAY_STORAGE } from "app/frontend/sway_utils/storage";

describe("funnelTracker", () => {
    beforeEach(() => {
        window.localStorage.clear();
        window.sessionStorage.clear();
        document.cookie = "";
        window.history.replaceState({}, "", "/");
        vi.restoreAllMocks();
    });

    afterEach(() => {
        window.localStorage.clear();
        window.sessionStorage.clear();
        window.history.replaceState({}, "", "/");
    });

    describe("getOrCreateVisitorToken", () => {
        it("generates and persists a visitor token when none exists", () => {
            const token = getOrCreateVisitorToken();
            expect(token).toBeDefined();
            expect(typeof token).toBe("string");
            expect(token.length).toBeGreaterThan(10);

            // Re-calling returns the same persisted token
            const cached = getOrCreateVisitorToken();
            expect(cached).toBe(token);
            expect(window.localStorage.getItem(SWAY_STORAGE.Local.Funnel.VisitorToken)).toBe(token);
            expect(document.cookie).toContain("sway_visitor_token=");
        });

        it("reuses existing token from localStorage", () => {
            window.localStorage.setItem(SWAY_STORAGE.Local.Funnel.VisitorToken, "existing-token-999");
            const token = getOrCreateVisitorToken();
            expect(token).toBe("existing-token-999");
        });
    });

    describe("captureReferralAttribution", () => {
        it("extracts referral from URL query parameter ?ref=", () => {
            window.history.replaceState({}, "", "/?ref=campaign_alpha");

            const key = captureReferralAttribution();
            expect(key).toBe("campaign_alpha");
            expect(window.localStorage.getItem(SWAY_STORAGE.Local.Funnel.AttributionKey)).toBe("campaign_alpha");
            expect(document.cookie).toContain("sway_attribution_key=campaign_alpha");
        });

        it("extracts short url prefix /s/:code", () => {
            window.history.replaceState({}, "", "/s/xyz789");

            const key = captureReferralAttribution();
            expect(key).toBe("s:xyz789");
        });

        it("reads attribution from cookie if present", () => {
            document.cookie = "sway_attribution_key=s%3Atest_share";
            const key = getAttributionKey();
            expect(key).toBe("s:test_share");
        });
    });

    describe("session step deduplication", () => {
        it("marks and detects recorded steps in session storage", () => {
            expect(hasStepBeenRecordedInSession("landing")).toBe(false);
            markStepRecordedInSession("landing");
            expect(hasStepBeenRecordedInSession("landing")).toBe(true);
        });
    });

    describe("trackFunnelStep and trackFunnelStepOnce", () => {
        it("dispatches telemetry via navigator.sendBeacon when available", () => {
            const sendBeaconMock = vi
                .fn<(url: string | URL, data?: BodyInit | null) => boolean>()
                .mockReturnValue(true);
            Object.defineProperty(navigator, "sendBeacon", {
                value: sendBeaconMock,
                configurable: true,
                writable: true,
            });

            trackFunnelStep("landing", { source: "test" });

            expect(sendBeaconMock).toHaveBeenCalledTimes(1);
            const [url, blob] = sendBeaconMock.mock.calls[0];
            expect(url).toBe("/api/v1/funnel_events");
            expect(blob).toBeInstanceOf(Blob);
        });

        it("falls back to keepalive fetch if sendBeacon is missing or returns false", () => {
            Object.defineProperty(navigator, "sendBeacon", {
                value: vi.fn<(url: string | URL, data?: BodyInit | null) => boolean>().mockReturnValue(false),
                configurable: true,
                writable: true,
            });

            const fetchMock = vi
                .fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>()
                .mockResolvedValue(new Response(JSON.stringify({ ok: true })));
            global.fetch = fetchMock;

            trackFunnelStep("phone_entered");

            expect(fetchMock).toHaveBeenCalledTimes(1);
            expect(fetchMock).toHaveBeenCalledWith(
                "/api/v1/funnel_events",
                expect.objectContaining({
                    method: "POST",
                    keepalive: true,
                }),
            );
        });

        it("trackFunnelStepOnce does not send the same step multiple times", () => {
            const sendBeaconMock = vi
                .fn<(url: string | URL, data?: BodyInit | null) => boolean>()
                .mockReturnValue(true);
            Object.defineProperty(navigator, "sendBeacon", {
                value: sendBeaconMock,
                configurable: true,
                writable: true,
            });

            trackFunnelStepOnce("landing");
            expect(sendBeaconMock).toHaveBeenCalledTimes(1);

            trackFunnelStepOnce("landing");
            expect(sendBeaconMock).toHaveBeenCalledTimes(1); // Not called second time
        });

        it("includes authenticity_token and X-CSRF-Token when csrf-token meta tag is present", () => {
            const meta = document.createElement("meta");
            meta.setAttribute("name", "csrf-token");
            meta.setAttribute("content", "test-csrf-token-123");
            document.head.appendChild(meta);

            try {
                Object.defineProperty(navigator, "sendBeacon", {
                    value: vi.fn<(url: string | URL, data?: BodyInit | null) => boolean>().mockReturnValue(false),
                    configurable: true,
                    writable: true,
                });

                const fetchMock = vi
                    .fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>()
                    .mockResolvedValue(new Response(JSON.stringify({ ok: true })));
                global.fetch = fetchMock;

                trackFunnelStep("phone_entered");

                expect(fetchMock).toHaveBeenCalledWith(
                    "/api/v1/funnel_events",
                    expect.objectContaining({
                        headers: expect.objectContaining({
                            "Content-Type": "application/json",
                            "X-CSRF-Token": "test-csrf-token-123",
                        }),
                        body: expect.stringContaining('"authenticity_token":"test-csrf-token-123"'),
                    }),
                );
            } finally {
                meta.remove();
            }
        });
    });
});
