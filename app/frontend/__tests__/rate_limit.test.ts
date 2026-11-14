import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { parseRetryAfter, throttleCopy } from "app/frontend/sway_utils/rate_limit";

// Freeze the clock, so `throttledUntil` — built from Date.now() — comes out the
// same every run.
const NOW = new Date("2026-07-07T00:00:00.000Z");

describe("parseRetryAfter", () => {
    beforeEach(() => {
        vi.useFakeTimers();
        vi.setSystemTime(NOW);
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it("returns nulls for a null response", () => {
        expect(parseRetryAfter(null)).toEqual({ throttledUntil: null, waitLabel: null });
    });

    it("returns nulls for a non-429 response", () => {
        expect(parseRetryAfter({ status: 200, headers: { "retry-after": "60" } })).toEqual({
            throttledUntil: null,
            waitLabel: null,
        });
    });

    // @lat: [[inertia-error-response-headers-shape#Why Inertia's rejected-request headers are a plain object, not Headers]]
    it("reads Retry-After from Inertia's plain lowercased-key header object (minutes)", () => {
        const result = parseRetryAfter({ status: 429, headers: { "retry-after": "120" } });
        expect(result.waitLabel).toBe("2 minutes");
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 120_000));
    });

    it("reads Retry-After from the plain header object (seconds)", () => {
        const result = parseRetryAfter({ status: 429, headers: { "retry-after": "45" } });
        expect(result.waitLabel).toBe("45 seconds");
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 45_000));
    });

    // A browser Headers object, which the optional fetch client sends, has to
    // keep working too.
    it("reads Retry-After from a Headers instance", () => {
        const result = parseRetryAfter({ status: 429, headers: new Headers({ "Retry-After": "90" }) });
        expect(result.waitLabel).toBe("2 minutes");
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 90_000));
    });

    it("words a one-hour Retry-After as about an hour", () => {
        const result = parseRetryAfter({ status: 429, headers: { "retry-after": "3600" } });
        expect(result.waitLabel).toBe("about an hour");
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 3_600_000));
        expect(throttleCopy("phone", result.waitLabel)).toBe(
            "Too many verification attempts. Please wait about an hour before trying again.",
        );
    });

    it("words a Retry-After of several hours in hours", () => {
        const result = parseRetryAfter({ status: 429, headers: { "retry-after": "7200" } });
        expect(result.waitLabel).toBe("about 2 hours");
    });

    it("falls back to a 60s throttle with a null label when the header is absent", () => {
        const result = parseRetryAfter({ status: 429, headers: {} });
        expect(result.waitLabel).toBeNull();
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 60_000));
    });

    it("falls back to a 60s throttle when the header is unparseable", () => {
        const result = parseRetryAfter({ status: 429, headers: { "retry-after": "soon" } });
        expect(result.waitLabel).toBeNull();
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 60_000));
    });

    it("falls back to a 60s throttle for a negative header value", () => {
        const result = parseRetryAfter({ status: 429, headers: { "retry-after": "-5" } });
        expect(result.waitLabel).toBeNull();
        expect(result.throttledUntil).toEqual(new Date(NOW.getTime() + 60_000));
    });
});

describe("throttleCopy", () => {
    it("builds sign-in copy with a wait label", () => {
        expect(throttleCopy("sign_in", "5 minutes")).toBe(
            "Too many sign-in attempts. Please wait 5 minutes before trying again.",
        );
    });

    it("builds sign-up copy without a wait label", () => {
        expect(throttleCopy("sign_up", null)).toBe("Too many sign-up attempts. Please try again later.");
    });

    it("maps phone and email scopes to the verification subject", () => {
        expect(throttleCopy("phone", "30 seconds")).toBe(
            "Too many verification attempts. Please wait 30 seconds before trying again.",
        );
        expect(throttleCopy("email", null)).toBe("Too many verification attempts. Please try again later.");
    });
});
