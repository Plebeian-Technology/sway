import { describe, it, expect } from "vitest";
import { resolveNotificationClickUrl } from "app/frontend/service-worker/resolveNotificationClickUrl";

// @lat: [[notification-click-url-guard#Why the notification-click URL guard is its own function]]
const ORIGIN = "https://app.sway.vote";

describe("resolveNotificationClickUrl", () => {
    it("resolves a relative path against our origin, preserving the query string", () => {
        expect(resolveNotificationClickUrl("/bills/42?tab=summary", ORIGIN)).toBe("/bills/42?tab=summary");
    });

    it("accepts an absolute same-origin url", () => {
        expect(resolveNotificationClickUrl(`${ORIGIN}/organizations`, ORIGIN)).toBe("/organizations");
    });

    it("defaults to / when the payload has no url", () => {
        expect(resolveNotificationClickUrl(undefined, ORIGIN)).toBe("/");
        expect(resolveNotificationClickUrl("", ORIGIN)).toBe("/");
    });

    it("rejects an absolute cross-origin url", () => {
        expect(resolveNotificationClickUrl("https://evil.example/phish", ORIGIN)).toBe("/");
    });

    it("rejects a protocol-relative url (//host resolves cross-origin)", () => {
        expect(resolveNotificationClickUrl("//evil.example/phish", ORIGIN)).toBe("/");
    });

    it("rejects non-http schemes (javascript:, data:)", () => {
        // Both parse fine against a base URL, but land on a different origin —
        // an opaque one, which the browser trusts with nothing.
        expect(resolveNotificationClickUrl("javascript:alert(1)", ORIGIN)).toBe("/");
        expect(resolveNotificationClickUrl("data:text/html,hi", ORIGIN)).toBe("/");
    });

    it("returns / for garbage that makes new URL throw, without throwing itself", () => {
        expect(() => resolveNotificationClickUrl("https://", ORIGIN)).not.toThrow();
        expect(resolveNotificationClickUrl("https://", ORIGIN)).toBe("/");
    });

    it("drops the fragment (hash is never forwarded to navigate)", () => {
        expect(resolveNotificationClickUrl("/bills/42#section", ORIGIN)).toBe("/bills/42");
    });
});
