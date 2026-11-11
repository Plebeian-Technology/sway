import { beforeEach, describe, expect, it, vi } from "vitest";
import { classifyPasskeyFailure } from "app/frontend/sway_utils/passkey_failure";

const notAllowed = () => new DOMException("The operation either timed out or was not allowed.", "NotAllowedError");

const setContext = ({ secure, hasWebAuthn }: { secure: boolean; hasWebAuthn: boolean }) => {
    vi.stubGlobal("window", {
        isSecureContext: secure,
        PublicKeyCredential: hasWebAuthn ? function PublicKeyCredential() {} : undefined,
        location: { origin: "https://sway.vote" },
    });
};

describe("classifyPasskeyFailure", () => {
    beforeEach(() => {
        setContext({ secure: true, hasWebAuthn: true });
    });

    it("stays silent when a person dismissed the sheet", () => {
        expect(classifyPasskeyFailure(notAllowed(), { elapsedMs: 4200 })).toBeNull();
    });

    it("reports a NotAllowedError that returned too fast for anyone to have seen a sheet", () => {
        expect(classifyPasskeyFailure(notAllowed(), { elapsedMs: 40 })).toEqual("refused-before-any-prompt");
    });

    it("reports an insecure context before looking at the error at all", () => {
        setContext({ secure: false, hasWebAuthn: true });

        // @lat: [[identity-and-access#Identity and access#The sign-in challenge says which ceremony to run]]
        expect(classifyPasskeyFailure(notAllowed(), { elapsedMs: 4200 })).toEqual("insecure-context");
    });

    it("reports a browser with no WebAuthn at all", () => {
        setContext({ secure: true, hasWebAuthn: false });

        expect(classifyPasskeyFailure(new TypeError("undefined is not an object"), { elapsedMs: 5 })).toEqual(
            "no-webauthn-support",
        );
    });

    it("stays silent when the caller aborted", () => {
        expect(classifyPasskeyFailure(new DOMException("Aborted", "AbortError"), { elapsedMs: 10 })).toBeNull();
    });

    it("reports a configuration fault by name", () => {
        expect(classifyPasskeyFailure(new DOMException("bad rp", "SecurityError"), { elapsedMs: 10 })).toEqual(
            "dom-exception-SecurityError",
        );
    });

    it("reports anything that is not a DOMException", () => {
        expect(classifyPasskeyFailure(new TypeError("boom"), { elapsedMs: 10 })).toEqual("not-a-dom-exception");
    });
});
