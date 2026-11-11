import { describe, it, expect } from "vitest";
import { parsePushPayload } from "app/frontend/service-worker/parsePushPayload";

// The push handler must never blow up on a broken message. A test cannot watch
// that crash, because it happens inside the service worker's push event, so
// these tests check the parsing function that was pulled out of it instead.
describe("parsePushPayload", () => {
    it("parses a valid JSON push payload into an object", () => {
        const payload = parsePushPayload(JSON.stringify({ title: "Hi", body: "There", icon: "/i.png" }));

        expect(payload).toEqual({ title: "Hi", body: "There", icon: "/i.png" });
    });

    it("returns null for a non-JSON payload without throwing", () => {
        expect(() => parsePushPayload("not json {")).not.toThrow();
        expect(parsePushPayload("not json {")).toBeNull();
    });

    it("returns null for JSON that is not an object", () => {
        expect(parsePushPayload("42")).toBeNull();
        expect(parsePushPayload("null")).toBeNull();
    });
});
