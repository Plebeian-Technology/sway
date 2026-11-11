import type { ErrorEvent } from "@sentry/react";
import { describe, expect, it } from "vitest";
import { scrubErrorEvent, scrubString } from "app/frontend/sway_utils/scrub_error_event";

// @lat: [[sway-error-scrubber-design#Why the backtracking guard allows two seconds]]
const BACKTRACKING_BOUND_MS = 2_000;

// @lat: [[browser-error-reporting#Browser error reporting#Development reports stay on this machine]]
describe("scrubErrorEvent", () => {
    // Assembled, not written out: gitleaks scans this file and an sk-ant-
    // literal is a finding whether or not it is real.
    const PLANTED_KEY = ["sk", "ant", "api03NOTREAL0000deadbeefTESTKEY"].join("-");
    const PLANTED_EMAIL = "planted.person@example-not-real.org";
    const PLANTED_PHONE = "410-555-0142";

    const eventWith = (message: string): ErrorEvent =>
        ({
            event_id: "abc123",
            exception: { values: [{ type: "TypeError", value: message }] },
        }) as unknown as ErrorEvent;

    const serialise = (event: ErrorEvent): string => JSON.stringify(scrubErrorEvent(event));

    describe("values planted in an exception message", () => {
        it("removes an Anthropic API key", () => {
            const output = serialise(eventWith(`upstream refused: ${PLANTED_KEY}`));

            expect(output).not.toContain(PLANTED_KEY);
            expect(output).toContain("[FILTERED_KEY]");
        });

        it("removes an email address", () => {
            const output = serialise(eventWith(`could not notify ${PLANTED_EMAIL}`));

            expect(output).not.toContain(PLANTED_EMAIL);
            expect(output).toContain("[FILTERED_EMAIL]");
        });

        it.each([
            ["dashed", "410-555-0142"],
            ["bracketed", "(410) 555-0142"],
            ["dotted", "410.555.0142"],
            ["spaced with country code", "+1 410 555 0142"],
            ["bare digits", "4105550142"],
        ])("removes a phone number written %s", (_shape, phone) => {
            const output = serialise(eventWith(`sms to ${phone} failed`));

            expect(output).not.toContain(phone);
            expect(output).toContain("[FILTERED_PHONE]");
        });
    });

    describe("everywhere else in the event", () => {
        it("removes values planted in a breadcrumb, not only in the exception", () => {
            const event = {
                breadcrumbs: [{ category: "console", message: `user typed ${PLANTED_EMAIL}` }],
            } as unknown as ErrorEvent;

            const output = serialise(event);

            expect(output).not.toContain(PLANTED_EMAIL);
        });

        it("removes values planted in a URL", () => {
            const event = {
                request: { url: `https://localhost:3333/search?q=${PLANTED_PHONE}` },
            } as unknown as ErrorEvent;

            expect(serialise(event)).not.toContain(PLANTED_PHONE);
        });

        it("removes values nested deep inside arbitrary extra data", () => {
            const event = {
                extra: { a: { b: { c: [{ d: `key is ${PLANTED_KEY}` }] } } },
            } as unknown as ErrorEvent;

            expect(serialise(event)).not.toContain(PLANTED_KEY);
        });
    });

    describe("things dropped whole rather than scrubbed", () => {
        it.each(["cookies", "headers", "authorization", "token", "password"])(
            "drops %s, which carries a session or a credential and helps nobody read a stack trace",
            (key) => {
                const event = { request: { [key]: "planted-secret-value" } } as unknown as ErrorEvent;

                const output = serialise(event);

                expect(output).not.toContain("planted-secret-value");
                expect(output).toContain("[FILTERED]");
            },
        );

        // @lat: [[sway-error-scrubber-design#Why a dropped request.headers map must stay a map]]
        it("keeps a dropped map a map rather than turning it into a string", () => {
            const event = {
                request: { headers: { Cookie: "planted-secret-value", Accept: "text/html" } },
            } as unknown as ErrorEvent;

            const scrubbed = scrubErrorEvent(event) as unknown as { request: { headers: unknown } };

            expect(scrubbed.request.headers).toEqual({});
            expect(serialise(event)).not.toContain("planted-secret-value");
        });

        it("drops them whatever their capitalisation", () => {
            const event = { request: { Cookie: "planted-secret-value" } } as unknown as ErrorEvent;

            expect(serialise(event)).not.toContain("planted-secret-value");
        });
    });

    // A rewritten event_id is not a valid id, so the collector rejects the
    // envelope and the error vanishes. The phone pattern hits a 32-char hex id
    // about 3.5% of the time, so this is roughly 1 report in 28.
    describe("Sentry protocol identifiers", () => {
        it.each(["event_id", "trace_id", "span_id", "parent_span_id", "timestamp"])(
            "leaves %s untouched even when it looks like a phone number",
            (key) => {
                const identifier = "abcd1234567890abcdef1234567890ab";
                const event = { [key]: identifier } as unknown as ErrorEvent;

                expect(serialise(event)).toContain(identifier);
            },
        );

        it("leaves a nested trace id alone", () => {
            const identifier = "ff1234567890ffffffffffffffffffff";
            const event = { contexts: { trace: { trace_id: identifier } } } as unknown as ErrorEvent;

            expect(serialise(event)).toContain(identifier);
        });

        it("still scrubs an ordinary field whose value looks the same", () => {
            const event = { extra: { note: "abcd1234567890abcdef" } } as unknown as ErrorEvent;

            expect(serialise(event)).toContain("FILTERED_PHONE");
        });

        // @lat: [[error-scrubber-empty-fingerprint-bug#Why scrubErrorEvent (the web beforeSend hook) also removes it]]
        it("removes an empty fingerprint, which would group every error together", () => {
            const event = { fingerprint: [], message: "x" } as unknown as ErrorEvent;

            expect("fingerprint" in scrubErrorEvent(event)).toBe(false);
        });

        it("keeps a fingerprint the app really chose", () => {
            const event = { fingerprint: ["checkout"] } as unknown as ErrorEvent;

            expect(scrubErrorEvent(event).fingerprint).toEqual(["checkout"]);
        });
    });

    describe("staying out of the way on the error path", () => {
        it("survives a circular object instead of exhausting the stack", () => {
            const cyclic: Record<string, unknown> = { name: "loop" };
            cyclic.self = cyclic;

            expect(() => scrubErrorEvent({ extra: cyclic } as unknown as ErrorEvent)).not.toThrow();
        });

        // seen must track the current path, not the whole traversal: the same
        // object referenced from two branches is not a cycle.
        it("keeps both copies of a value referenced twice", () => {
            const props = { bill: "62", note: "ordinary text" };
            const event = { extra: { props, snapshot: props } } as unknown as ErrorEvent;

            const output = JSON.parse(serialise(event));

            expect(output.extra.props).toEqual(props);
            expect(output.extra.snapshot).toEqual(props);
        });

        // The email pattern is quadratic, so redacting before capping took 4s on
        // 50,000 chars — on the error path, blocking the main thread.
        it("stays fast on a huge string instead of blocking on backtracking", () => {
            const huge = "a.b-c_d%e+f".repeat(5_000);

            const started = performance.now();
            scrubString(huge);

            expect(performance.now() - started).toBeLessThan(BACKTRACKING_BOUND_MS);
        });

        it("caps one enormous string so a whole column cannot ride along", () => {
            const huge = "x".repeat(50_000);

            const output = scrubString(huge);

            expect(output.length).toBeLessThan(3_000);
            expect(output).toContain("truncated");
        });

        it("never drops the event, because a report that is not sent explains nothing", () => {
            expect(scrubErrorEvent(eventWith("something broke"))).not.toBeNull();
        });

        // Deliberate over-reach, pinned so it is a decision rather than a
        // surprise. Sway stores phone numbers as bare digits, so the pattern
        // must match them and any other 10-digit run goes with them.
        it("also scrubs any bare 10-digit run, such as an id or a timestamp", () => {
            expect(serialise(eventWith("row 1699999999 failed"))).not.toContain("1699999999");
        });

        it("leaves shorter and longer digit runs alone", () => {
            const message = "bill 62 row 123456789012 ok";

            expect(serialise(eventWith(message))).toContain(message);
        });

        it("leaves an ordinary message alone", () => {
            const message = "Cannot read properties of undefined (reading 'bills')";

            expect(serialise(eventWith(message))).toContain(message);
        });
    });

    // Pinned so nobody assumes addresses are covered. What keeps testimony out
    // is upstream: no bodies, cookies or headers are sent, and JS frames carry
    // no locals.
    describe("the limit of what a pattern can find", () => {
        it("does NOT remove a street address written as prose", () => {
            const address = "100 N Holliday St";

            expect(serialise(eventWith(`geocoding failed for ${address}`))).toContain(address);
        });
    });
});
