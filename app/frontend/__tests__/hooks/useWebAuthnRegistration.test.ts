import { HttpResponseError } from "@inertiajs/core";
import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, type Mock, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    clearIdentityCaches: vi.fn<() => void>(),
    prepareIdentityChange: vi.fn<() => Promise<void>>(),
    transform: vi.fn<(...args: unknown[]) => unknown>(),
    post: vi.fn<(...args: unknown[]) => unknown>(),
    routerPost: vi.fn<(...args: unknown[]) => unknown>(),
    notify: vi.fn<(...args: unknown[]) => unknown>(),
    handleError: vi.fn<(...args: unknown[]) => unknown>(),
    create: vi.fn<(...args: unknown[]) => unknown>(),
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
    create: mocks.create,
}));

import { useWebAuthnRegistration } from "app/frontend/hooks/authentication/useWebAuthnRegistration";

const PHONE = "4105551234";

describe("useWebAuthnRegistration", () => {
    let onThrottled: Mock<(until: Date | null) => void>;

    beforeEach(() => {
        vi.clearAllMocks();
        mocks.prepareIdentityChange.mockResolvedValue(undefined);
        onThrottled = vi.fn<(until: Date | null) => void>();
    });

    describe("startRegistration", () => {
        it("drives the WebAuthn create() ceremony when the server returns creation options", async () => {
            const options = { challenge: "abc", rp: { name: "Sway" } };
            const attestation = { id: "cred-1", type: "public-key" };
            mocks.post.mockResolvedValue(options);
            mocks.create.mockResolvedValue(attestation);

            const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));
            let returned;
            await act(async () => {
                returned = await result.current.startRegistration(PHONE);
            });

            expect(mocks.transform).toHaveBeenCalled();
            expect(mocks.post).toHaveBeenCalledWith("/users/webauthn/registration");
            expect(mocks.create).toHaveBeenCalledWith({ publicKey: options, signal: expect.any(AbortSignal) });
            expect(returned).toEqual(attestation);
        });

        it("shows a sign-up throttle toast and reports the throttle window on a 429", async () => {
            mocks.post.mockRejectedValue({ response: { status: 429, headers: { "retry-after": "45" } } });
            const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));

            await act(async () => {
                await result.current.startRegistration(PHONE);
            });

            expect(mocks.notify).toHaveBeenCalledWith({
                level: "error",
                title: "Too many sign-up attempts. Please wait 45 seconds before trying again.",
            });
            expect(onThrottled).toHaveBeenCalledWith(expect.any(Date));
        });

        it("directs existing-passkey accounts to sign-in without opening enrollment", async () => {
            mocks.post.mockRejectedValue(new HttpResponseError("Conflict", { status: 409, data: "{}", headers: {} }));
            const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));

            await act(async () => {
                await result.current.startRegistration(PHONE);
            });

            expect(mocks.notify).toHaveBeenCalledWith({
                level: "error",
                title: "This phone already has a Sway account. Sign in with your passkey, or contact Sway support if you've lost access.",
            });
            expect(mocks.create).not.toHaveBeenCalled();
            expect(mocks.handleError).not.toHaveBeenCalled();
            expect(result.current.isLoading).toBe(false);
        });

        it("routes non-429 errors through handleError without re-throwing", async () => {
            const boom = { response: { status: 500 } };
            mocks.post.mockRejectedValue(boom);
            const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));

            await act(async () => {
                // It must succeed, not fail: for anything other than a 429,
                // registration passes the error to handleError and carries on.
                await expect(result.current.startRegistration(PHONE)).resolves.toBeUndefined();
            });
            expect(mocks.handleError).toHaveBeenCalledWith(boom);
            expect(onThrottled).not.toHaveBeenCalled();
        });
    });

    it("does not submit credentials when browser cache migration fails", async () => {
        mocks.prepareIdentityChange.mockRejectedValue(new Error("internal update failure"));
        const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));
        await act(async () => {
            await result.current.verifyRegistration(PHONE, { id: "cred" } as never);
        });
        expect(mocks.routerPost).not.toHaveBeenCalled();
        expect(mocks.notify).toHaveBeenCalledWith({
            level: "error",
            title: "Sway could not finish updating. Reload this page and try again.",
        });
        expect(result.current.isLoading).toBe(false);
    });

    describe("verifyRegistration", () => {
        it("posts phone + passkey_label + the spread credential to the registration callback", async () => {
            const credential = { id: "cred-1", rawId: "raw", type: "public-key" };
            const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));

            await act(async () => {
                await result.current.verifyRegistration(PHONE, credential as never);
            });

            expect(mocks.routerPost).toHaveBeenCalledWith(
                "/users/webauthn/registration/callback",
                { phone: PHONE, passkey_label: "Sway", ...credential },
                expect.objectContaining({
                    preserveState: false,
                    onBeforeUpdate: mocks.clearIdentityCaches,
                    onFinish: expect.any(Function),
                }),
            );
        });

        it("does nothing when phone or credential is missing", async () => {
            const credential = { id: "cred-1", type: "public-key" };
            const { result } = renderHook(() => useWebAuthnRegistration(onThrottled));

            await act(async () => {
                await result.current.verifyRegistration("", credential as never);
                await result.current.verifyRegistration(PHONE, undefined as never);
            });

            expect(mocks.routerPost).not.toHaveBeenCalled();
            expect(mocks.prepareIdentityChange).not.toHaveBeenCalled();
        });
    });
});
