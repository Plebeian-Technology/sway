import { scrubErrorEvent, scrubString } from "../../src/observability/scrub_error_event";

// Every planted value below is invented.
const KEY = ["sk", "ant", "api03NOTREAL0000deadbeefTESTKEY"].join("-");
const EMAIL = "planted.person@example-not-real.org";

// @lat: [[sway-error-scrubber-design#Why dropped() preserves type in scrub_error_event.ts]]
const BACKTRACKING_BOUND_MS = 2_000;

describe("scrubString", () => {
    it("removes an Anthropic key", () => {
        expect(scrubString(`upstream refused: ${KEY}`)).toBe("upstream refused: [FILTERED_KEY]");
    });

    it("removes an email address", () => {
        expect(scrubString(`could not notify ${EMAIL}`)).toBe("could not notify [FILTERED_EMAIL]");
    });

    it.each(["410-555-0142", "(410) 555-0142", "410.555.0142", "+1 410 555 0142", "4105550142"])(
        "removes a phone written as %s",
        (phone) => {
            expect(scrubString(`sms to ${phone} failed`)).toBe("sms to [FILTERED_PHONE] failed");
        },
    );

    it("caps a huge value so a whole column cannot ride along", () => {
        const result = scrubString("x".repeat(50_000));

        expect(result.length).toBeLessThan(3_000);
        expect(result).toContain("truncated");
    });

    // @lat: [[sway-error-scrubber-design#Why dropped() preserves type in scrub_error_event.ts]]
    it("stays fast on a huge string instead of blocking on backtracking", () => {
        const started = Date.now();
        scrubString("a.b-c_d%e+f".repeat(5_000));

        expect(Date.now() - started).toBeLessThan(BACKTRACKING_BOUND_MS);
    });

    it("leaves an ordinary message alone", () => {
        expect(scrubString("undefined is not an object")).toBe("undefined is not an object");
    });
});

describe("scrubErrorEvent", () => {
    it("reaches values nested in arrays and objects", () => {
        const scrubbed = scrubErrorEvent({ a: [{ b: `key ${KEY}` }] });

        expect(JSON.stringify(scrubbed)).not.toContain(KEY);
    });

    it.each(["cookie", "cookies", "headers", "authorization", "token", "password"])(
        "drops %s whole, since it carries a session or credential",
        (key) => {
            const scrubbed = scrubErrorEvent({ [key]: "planted-secret-value" }) as Record<string, unknown>;

            expect(scrubbed[key]).toBe("[FILTERED]");
        },
    );

    // @lat: [[sway-error-scrubber-design#Why dropped() preserves type in scrub_error_event.ts]]
    it("keeps a dropped map a map, so the native SDK can still read the event", () => {
        const scrubbed = scrubErrorEvent({
            request: { headers: { Cookie: "planted-secret-value", Accept: "text/html" } },
        }) as { request: { headers: unknown } };

        expect(scrubbed.request.headers).toEqual({});
        expect(typeof scrubbed.request.headers).toBe("object");
    });

    it("keeps a dropped list a list", () => {
        const scrubbed = scrubErrorEvent({ cookies: ["a=1", "b=2"] }) as Record<string, unknown>;

        expect(scrubbed.cookies).toEqual([]);
    });

    // @lat: [[error-scrubber-empty-fingerprint-bug#Why the scrub-error-event test calls this Android-only]]
    it("removes an empty fingerprint, which would group every error together", () => {
        const scrubbed = scrubErrorEvent({ fingerprint: [], message: "x" }) as Record<string, unknown>;

        expect("fingerprint" in scrubbed).toBe(false);
    });

    it("keeps a fingerprint the app really chose", () => {
        const scrubbed = scrubErrorEvent({ fingerprint: ["checkout-failure"] }) as Record<string, unknown>;

        expect(scrubbed.fingerprint).toEqual(["checkout-failure"]);
    });

    // @lat: [[sway-error-scrubber-design#Why dropped() preserves type in scrub_error_event.ts]]
    it.each(["event_id", "trace_id", "span_id", "parent_span_id", "timestamp"])("leaves %s untouched", (key) => {
        const id = "1699999999abcdef1699999999abcdef";
        const scrubbed = scrubErrorEvent({ [key]: id }) as Record<string, unknown>;

        expect(scrubbed[key]).toBe(id);
    });

    it("keeps a value that appears twice, rather than calling the second one a cycle", () => {
        const shared = { note: "hello" };
        const scrubbed = scrubErrorEvent({ a: shared, b: shared }) as Record<string, unknown>;

        expect(scrubbed.b).toEqual({ note: "hello" });
    });

    it("survives a real cycle instead of throwing while handling an error", () => {
        const cyclic: Record<string, unknown> = { name: "loop" };
        cyclic.self = cyclic;

        expect(() => scrubErrorEvent(cyclic)).not.toThrow();
    });
});
