import { isSafeCitationUrl } from "../../src/utils/safeUrl";

describe("isSafeCitationUrl", () => {
    test("accepts valid https URLs", () => {
        expect(isSafeCitationUrl("https://www.thebaltimorebanner.com/transit-funding")).toBe(true);
        expect(isSafeCitationUrl("https://mgaleg.maryland.gov/2026RS/bills/hb/hb0001f.pdf")).toBe(true);
    });

    test("accepts valid http URLs", () => {
        expect(isSafeCitationUrl("http://example.com/news/article")).toBe(true);
    });

    test("rejects null, undefined, and non-string inputs", () => {
        expect(isSafeCitationUrl(null)).toBe(false);
        expect(isSafeCitationUrl(undefined)).toBe(false);
        expect(isSafeCitationUrl("")).toBe(false);
        expect(isSafeCitationUrl("   ")).toBe(false);
    });

    test("rejects unsafe schemes", () => {
        expect(isSafeCitationUrl("javascript:alert(1)")).toBe(false);
        expect(isSafeCitationUrl("file:///etc/passwd")).toBe(false);
        expect(isSafeCitationUrl("data:text/html,<script>alert(1)</script>")).toBe(false);
        expect(isSafeCitationUrl("intent://example.com#Intent;scheme=bad;end")).toBe(false);
        expect(isSafeCitationUrl("vbscript:msgbox(1)")).toBe(false);
        expect(isSafeCitationUrl("tel:1234567890")).toBe(false);
        expect(isSafeCitationUrl("mailto:user@example.com")).toBe(false);
    });

    test("rejects URLs containing user credentials", () => {
        expect(isSafeCitationUrl("https://admin:secret@example.com/article")).toBe(false);
        expect(isSafeCitationUrl("https://user@example.com/article")).toBe(false);
    });

    test("rejects malformed or unparseable URLs", () => {
        expect(isSafeCitationUrl("not-a-url")).toBe(false);
        expect(isSafeCitationUrl("https://")).toBe(false);
        expect(isSafeCitationUrl("https://[invalid-ipv6")).toBe(false);
    });
});
