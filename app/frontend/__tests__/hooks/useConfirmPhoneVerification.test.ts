import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, type Mock, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    isRegistering: false,
    passkeyDismissed: false,
    clearPasskeyDismissed: vi.fn<() => void>(),
    transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
    put: vi.fn<(path: string) => Promise<unknown>>(),
    notify: vi.fn<(message: unknown) => void>(),
    handleError: vi.fn<() => void>(),
    startRegistration: vi.fn<(phone: string) => Promise<unknown>>(),
    verifyRegistration: vi.fn<(phone: string, credential: unknown) => Promise<void>>(),
}));

vi.mock("@inertiajs/react", () => ({
    useHttp: () => ({ transform: mocks.transform, put: mocks.put, processing: false }),
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: mocks.notify,
    handleError: mocks.handleError,
}));

// When the code checks out, confirm goes straight on to creating a passkey (the
// WebAuthn registration ceremony). Fake that step, so this test covers only the
// phone-confirmation decisions.
vi.mock("app/frontend/hooks/authentication/useWebAuthnRegistration", () => ({
    useWebAuthnRegistration: () => ({
        isLoading: mocks.isRegistering,
        passkeyDismissed: mocks.passkeyDismissed,
        clearPasskeyDismissed: mocks.clearPasskeyDismissed,
        startRegistration: mocks.startRegistration,
        verifyRegistration: mocks.verifyRegistration,
    }),
}));

import { useConfirmPhoneVerification } from "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification";

const PHONE = "4105551234";
const CODE = "123456";

describe("useConfirmPhoneVerification", () => {
    let onThrottled: Mock<(until: Date | null) => void>;

    beforeEach(() => {
        vi.clearAllMocks();
        mocks.isRegistering = false;
        mocks.passkeyDismissed = false;
        mocks.verifyRegistration.mockResolvedValue(undefined);
        onThrottled = vi.fn<(until: Date | null) => void>();
    });

    it("puts the code and chains into registration when the code is correct", async () => {
        const publicKey = { id: "cred-1", type: "public-key" };
        mocks.put.mockResolvedValue({ success: true, message: "ok" });
        mocks.startRegistration.mockResolvedValue(publicKey);
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });

        expect(mocks.transform).toHaveBeenCalled();
        const transformFn = mocks.transform.mock.calls[0][0] as unknown as () => unknown;
        expect(transformFn()).toEqual({ phone_verification: { phone: PHONE, code: CODE } });
        expect(mocks.put).toHaveBeenCalledWith("/phone_verification/0");
        expect(mocks.startRegistration).toHaveBeenCalledWith(PHONE);
        expect(mocks.verifyRegistration).toHaveBeenCalledWith(PHONE, publicKey);
    });

    it("stays loading while nested passkey verification is preparing the browser", () => {
        mocks.isRegistering = true;
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));
        expect(result.current.isLoading).toBe(true);
    });

    it("passes the passkey dismissal through to the panel", () => {
        mocks.passkeyDismissed = true;
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        expect(result.current.passkeyDismissed).toBe(true);
        result.current.clearPasskeyDismissed();
        expect(mocks.clearPasskeyDismissed).toHaveBeenCalled();
    });

    it("handles a rejected registration verification before confirmation returns", async () => {
        const failure = new Error("verification failed");
        mocks.put.mockResolvedValue({ success: true });
        mocks.startRegistration.mockResolvedValue({ id: "cred-1" });
        mocks.verifyRegistration.mockRejectedValue(failure);
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));
        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });
        expect(mocks.handleError).toHaveBeenCalledWith(failure);
    });

    it("does not verify registration when the ceremony yields no credential", async () => {
        mocks.put.mockResolvedValue({ success: true });
        mocks.startRegistration.mockResolvedValue(undefined);
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });

        expect(mocks.startRegistration).toHaveBeenCalledWith(PHONE);
        expect(mocks.verifyRegistration).not.toHaveBeenCalled();
    });

    it("shows the server's verification error and stops before passkey registration", async () => {
        mocks.put.mockResolvedValue({ success: false, error: "Code not found." });
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });

        expect(mocks.notify).toHaveBeenCalledWith({ level: "error", title: "Code not found." });
        expect(mocks.startRegistration).not.toHaveBeenCalled();
        expect(mocks.verifyRegistration).not.toHaveBeenCalled();
    });

    it("falls back to 'Incorrect Code' when the failed reply has no error", async () => {
        mocks.put.mockResolvedValue({ success: false });
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });

        expect(mocks.notify).toHaveBeenCalledWith({ level: "error", title: "Incorrect Code" });
        expect(mocks.startRegistration).not.toHaveBeenCalled();
    });

    it("shows a verification throttle toast on a 429", async () => {
        mocks.put.mockRejectedValue({ response: { status: 429, headers: { "retry-after": "30" } } });
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });

        expect(mocks.notify).toHaveBeenCalledWith({
            level: "error",
            title: "Too many verification attempts. Please wait 30 seconds before trying again.",
        });
        expect(onThrottled).toHaveBeenCalledWith(expect.any(Date));
    });

    it("routes non-429 confirmation failures to handleError", async () => {
        const failure = new Error("network down");
        mocks.put.mockRejectedValue(failure);
        const { result } = renderHook(() => useConfirmPhoneVerification(onThrottled));

        await act(async () => {
            await result.current.confirm(PHONE, CODE);
        });

        expect(mocks.handleError).toHaveBeenCalledWith(failure);
    });
});
