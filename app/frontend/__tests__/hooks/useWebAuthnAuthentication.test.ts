import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, type Mock, vi } from "vitest";

// Fake only the parts that talk to the outside world. The real rate_limit code
// stays in place — parseRetryAfter and throttleCopy work purely off their
// inputs — so the 429 checks prove the real wait-message is built from a
// Retry-After header shaped the way production sends it: a plain object.
const mocks = vi.hoisted(() => ({
    clearIdentityCaches: vi.fn<() => void>(),
    prepareIdentityChange: vi.fn<() => Promise<void>>(),
    transform: vi.fn<(data: unknown) => unknown>(),
    post: vi.fn<(url: string, data?: unknown, config?: unknown) => Promise<unknown>>(),
    routerPost: vi.fn<(url: string, data?: unknown, config?: unknown) => void>(),
    notify: vi.fn<(message: unknown) => void>(),
    handleError: vi.fn<(error: unknown) => void>(),
    get: vi.fn<(url: string) => Promise<unknown>>(),
    classifyReason: vi.fn<() => string | null>(),
}));

vi.mock("app/frontend/sway_utils/passkey_failure", () => ({
    reportPasskeyFailure: () => mocks.classifyReason(),
}));

vi.mock("app/frontend/hooks/authentication/prepareIdentityChange", () => ({
    clearIdentityCaches: mocks.clearIdentityCaches,
    prepareIdentityChange: mocks.prepareIdentityChange,
    IDENTITY_CHANGE_RETRY: "Sway could not finish updating. Reload this page and try again.",
}));

vi.mock("@inertiajs/react", () => ({
    useHttp: () => ({ transform: mocks.transform, post: mocks.post, processing: false }),
    router: { post: mocks.routerPost },
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: mocks.notify,
    handleError: mocks.handleError,
    logDev: vi.fn<() => void>(),
    get: mocks.get,
}));

import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";

const PHONE = "4105551234";

describe("useWebAuthnAuthentication", () => {
    let onThrottled: Mock<(until: Date | null) => void>;

    beforeEach(() => {
        vi.clearAllMocks();
        mocks.prepareIdentityChange.mockResolvedValue(undefined);
        mocks.classifyReason.mockReturnValue(null);
        onThrottled = vi.fn<(until: Date | null) => void>();
    });

    describe("startAuthentication", () => {
        it("short-circuits and returns success when the server replies with the sms flow", async () => {
            mocks.post.mockResolvedValue({ flow: "sms", success: true });
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            let returned;
            await act(async () => {
                returned = await result.current.startAuthentication(PHONE);
            });

            expect(returned).toBe(true);
            expect(mocks.transform).toHaveBeenCalled();
            expect(mocks.post).toHaveBeenCalledWith("/users/webauthn/sessions");
            // The SMS path must NOT start the passkey (WebAuthn) prompt.
            expect(mocks.get).not.toHaveBeenCalled();
        });

        it("returns false when the sms flow reports a failed send", async () => {
            mocks.post.mockResolvedValue({ flow: "sms", success: false });
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            let returned;
            await act(async () => {
                returned = await result.current.startAuthentication(PHONE);
            });

            expect(returned).toBe(false);
            expect(mocks.get).not.toHaveBeenCalled();
        });

        it("returns enroll without a WebAuthn get() when the server answers the enroll flow", async () => {
            mocks.post.mockResolvedValue({ flow: "enroll" });
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            let returned;
            await act(async () => {
                returned = await result.current.startAuthentication(PHONE);
            });

            expect(returned).toBe("enroll");
            expect(mocks.get).not.toHaveBeenCalled();
        });

        it("drives the WebAuthn get() ceremony when the server returns the passkey flow", async () => {
            const options = { challenge: "abc", allowCredentials: [] };
            const assertion = { id: "cred-1", type: "public-key" };
            mocks.post.mockResolvedValue({ flow: "passkey", options });
            mocks.get.mockResolvedValue(assertion);

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            let returned;
            await act(async () => {
                returned = await result.current.startAuthentication(PHONE);
            });

            expect(mocks.get).toHaveBeenCalledWith({ publicKey: options, signal: expect.any(AbortSignal) });
            expect(returned).toEqual(assertion);
        });

        it("shows a sign-in throttle toast and reports the throttle window on a 429", async () => {
            mocks.post.mockRejectedValue({ response: { status: 429, headers: { "retry-after": "120" } } });
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            let returned;
            await act(async () => {
                returned = await result.current.startAuthentication(PHONE);
            });

            expect(returned).toBeUndefined();
            expect(mocks.notify).toHaveBeenCalledWith({
                level: "error",
                title: "Too many sign-in attempts. Please wait 2 minutes before trying again.",
            });
            expect(onThrottled).toHaveBeenCalledWith(expect.any(Date));
        });

        it("re-throws non-429 errors instead of swallowing them", async () => {
            mocks.post.mockRejectedValue({ response: { status: 500 } });
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            await act(async () => {
                await expect(result.current.startAuthentication(PHONE)).rejects.toEqual({
                    response: { status: 500 },
                });
            });
            expect(onThrottled).not.toHaveBeenCalled();
            expect(mocks.notify).not.toHaveBeenCalled();
        });
    });

    describe("startDiscoverableAuthentication", () => {
        it("posts to the discoverable challenge route and runs the ceremony with the returned options", async () => {
            const options = { challenge: "disc", allowCredentials: [] };
            const assertion = { id: "cred-9", type: "public-key" };
            mocks.post.mockResolvedValue({ flow: "passkey", options });
            mocks.get.mockResolvedValue(assertion);

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            let returned;
            await act(async () => {
                returned = await result.current.startDiscoverableAuthentication();
            });

            expect(mocks.post).toHaveBeenCalledWith("/users/webauthn/sessions/discoverable_challenge");
            expect(mocks.get).toHaveBeenCalledWith({ publicKey: options });
            expect(returned).toEqual(assertion);
        });

        it("returns undefined (no throw) when the ceremony is cancelled or finds no passkey", async () => {
            mocks.post.mockResolvedValue({ flow: "passkey", options: { challenge: "disc" } });
            // navigator.credentials.get fails with NotAllowedError when the person cancels or has no passkey.
            mocks.get.mockRejectedValue(Object.assign(new Error("cancelled"), { name: "NotAllowedError" }));

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            let returned: unknown = "sentinel";
            await act(async () => {
                returned = await result.current.startDiscoverableAuthentication();
            });

            expect(returned).toBeUndefined();
        });

        // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
        it("leaves discoverableFailure null when the classifier reads the failure as a person", async () => {
            mocks.post.mockResolvedValue({ flow: "passkey", options: { challenge: "disc" } });
            mocks.classifyReason.mockReturnValue(null);
            mocks.get.mockRejectedValue(Object.assign(new Error("cancelled"), { name: "NotAllowedError" }));

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            await act(async () => {
                await result.current.startDiscoverableAuthentication();
            });

            expect(result.current.discoverableFailure).toBeNull();
        });

        // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
        it("sets discoverableFailure to the reason when the failure was not the reader's doing", async () => {
            mocks.post.mockResolvedValue({ flow: "passkey", options: { challenge: "disc" } });
            mocks.classifyReason.mockReturnValue("refused-before-any-prompt");
            mocks.get.mockRejectedValue(Object.assign(new Error("refused"), { name: "NotAllowedError" }));

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            await act(async () => {
                await result.current.startDiscoverableAuthentication();
            });

            expect(result.current.discoverableFailure).toBe("refused-before-any-prompt");
        });

        // The ceremony never ran at all, so nobody could have cancelled it.
        it("sets discoverableFailure when the challenge request itself fails", async () => {
            mocks.post.mockRejectedValue(new TypeError("Failed to fetch"));

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            await act(async () => {
                await result.current.startDiscoverableAuthentication();
            });

            expect(result.current.discoverableFailure).toBe("challenge-request-failed");
            expect(mocks.get).not.toHaveBeenCalled();
        });

        it("clears a previous failure when a fresh attempt starts", async () => {
            mocks.post.mockRejectedValueOnce(new TypeError("Failed to fetch"));
            const assertion = { id: "cred-9", type: "public-key" };
            mocks.post.mockResolvedValue({ flow: "passkey", options: { challenge: "disc" } });
            mocks.get.mockResolvedValue(assertion);

            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
            await act(async () => {
                await result.current.startDiscoverableAuthentication();
            });
            expect(result.current.discoverableFailure).toBe("challenge-request-failed");

            await act(async () => {
                await result.current.startDiscoverableAuthentication();
            });
            expect(result.current.discoverableFailure).toBeNull();
        });
    });

    it("withholds credential submission while identity preparation is pending", async () => {
        let finishPreparation: () => void = () => {};
        mocks.prepareIdentityChange.mockImplementation(
            () =>
                new Promise<void>((resolve) => {
                    finishPreparation = resolve;
                }),
        );
        const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
        let submission: Promise<void> | undefined;
        act(() => {
            submission = result.current.verifyDiscoverableAuthentication({ id: "cred" } as never);
        });
        expect(mocks.routerPost).not.toHaveBeenCalled();
        expect(result.current.isLoading).toBe(true);
        await act(async () => {
            finishPreparation();
            await submission;
        });
        expect(mocks.routerPost).toHaveBeenCalledOnce();
    });

    it("does not submit credentials when browser cache migration fails", async () => {
        mocks.prepareIdentityChange.mockRejectedValue(new Error("internal update failure"));
        const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));
        await act(async () => {
            await result.current.verifyDiscoverableAuthentication({ id: "cred" } as never);
        });
        expect(mocks.routerPost).not.toHaveBeenCalled();
        expect(mocks.notify).toHaveBeenCalledWith({
            level: "error",
            title: "Sway could not finish updating. Reload this page and try again.",
        });
        expect(result.current.isLoading).toBe(false);
    });

    describe("verifyDiscoverableAuthentication", () => {
        it("posts the credential to the discoverable callback route with no phone", async () => {
            const credential = { id: "cred-9", type: "public-key" };
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            await act(async () => {
                await result.current.verifyDiscoverableAuthentication(credential as never);
            });

            expect(mocks.routerPost).toHaveBeenCalledWith(
                "/users/webauthn/sessions/discoverable_callback",
                { publicKeyCredential: credential },
                { preserveState: false, onBeforeUpdate: mocks.clearIdentityCaches, onFinish: expect.any(Function) },
            );
        });
    });

    describe("verifyAuthentication", () => {
        it("posts {phone, publicKeyCredential} to the session callback route", async () => {
            const credential = { id: "cred-1", type: "public-key" };
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            await act(async () => {
                await result.current.verifyAuthentication(PHONE, credential as never);
            });

            expect(mocks.routerPost).toHaveBeenCalledWith(
                "/users/webauthn/sessions/callback",
                { phone: PHONE, publicKeyCredential: credential },
                { preserveState: false, onBeforeUpdate: mocks.clearIdentityCaches, onFinish: expect.any(Function) },
            );
        });

        it("does nothing when the credential is missing", async () => {
            const { result } = renderHook(() => useWebAuthnAuthentication(onThrottled));

            await act(async () => {
                await result.current.verifyAuthentication(PHONE, undefined as never);
            });

            expect(mocks.routerPost).not.toHaveBeenCalled();
            expect(mocks.prepareIdentityChange).not.toHaveBeenCalled();
        });
    });
});
