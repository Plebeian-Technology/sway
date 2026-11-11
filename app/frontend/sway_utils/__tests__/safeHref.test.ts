import { describe, expect, it } from "vitest";
import { isSafeExternalHref, isSafeUrl } from "app/frontend/sway_utils/safeHref";

describe("safeHref", () => {
    describe("isSafeExternalHref", () => {
        it("accepts valid https and http URLs", () => {
            expect(isSafeExternalHref("https://example.com")).toBe(true);
            expect(isSafeExternalHref("http://example.com")).toBe(true);
        });

        it("accepts relative paths against window.location.origin", () => {
            expect(isSafeExternalHref("/admin/bills")).toBe(true);
            expect(isSafeExternalHref("/dashboard")).toBe(true);
        });

        it("rejects non-http/https protocols", () => {
            expect(isSafeExternalHref("javascript:alert(1)")).toBe(false);
            expect(isSafeExternalHref("file:///etc/passwd")).toBe(false);
            expect(isSafeExternalHref("file:///")).toBe(false);
            expect(isSafeExternalHref("data:text/html,test")).toBe(false);
        });

        it("rejects null, undefined, and empty string", () => {
            expect(isSafeExternalHref("")).toBe(false);
            expect(isSafeExternalHref("   ")).toBe(false);
            expect(isSafeExternalHref("\t\n")).toBe(false);
            expect(isSafeExternalHref(null)).toBe(false);
            expect(isSafeExternalHref(undefined)).toBe(false);
            expect(isSafeExternalHref(123)).toBe(false);
        });
    });

    describe("isSafeUrl", () => {
        it("accepts standard https and http URLs with hostname", () => {
            expect(isSafeUrl("https://sway.vote")).toBe(true);
            expect(isSafeUrl("http://example.com/article/123")).toBe(true);
            expect(isSafeUrl("https://thebaltimorebanner.com/politics?tab=1")).toBe(true);
        });

        it("rejects file:/// schemes", () => {
            expect(isSafeUrl("file:///")).toBe(false);
            expect(isSafeUrl("file:///etc/passwd")).toBe(false);
            expect(isSafeUrl("FILE:///C:/Windows/win.ini")).toBe(false);
        });

        it("rejects javascript:, data:, and other non-web schemes", () => {
            expect(isSafeUrl("javascript:alert(1)")).toBe(false);
            expect(isSafeUrl("data:text/html,test")).toBe(false);
            expect(isSafeUrl("blob:https://example.com/123")).toBe(false);
            expect(isSafeUrl("ftp://files.example.com")).toBe(false);
        });

        it("rejects URLs with embedded credentials", () => {
            expect(isSafeUrl("https://user:pass@example.com")).toBe(false);
            expect(isSafeUrl("http://admin@example.com")).toBe(false);
        });

        it("rejects relative paths or bare strings", () => {
            expect(isSafeUrl("/relative/path")).toBe(false);
            expect(isSafeUrl("not-a-url")).toBe(false);
        });

        it("rejects empty, null, or undefined values", () => {
            expect(isSafeUrl("")).toBe(false);
            expect(isSafeUrl("   ")).toBe(false);
            expect(isSafeUrl(null)).toBe(false);
            expect(isSafeUrl(undefined)).toBe(false);
            expect(isSafeUrl(42)).toBe(false);
        });
    });
});
