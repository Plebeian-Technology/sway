import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, type Mock, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
    post: vi.fn<(url: string, data?: unknown) => Promise<unknown>>(),
    notify: vi.fn<(...args: unknown[]) => void>(),
}));

vi.mock("@inertiajs/react", () => ({
    useHttp: () => ({ transform: mocks.transform, post: mocks.post, processing: false }),
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: mocks.notify,
}));

import { useSendPhoneVerification } from "app/frontend/hooks/authentication/phone/useSendPhoneVerification";

const PHONE = "4105551234";

describe("useSendPhoneVerification", () => {
    let onThrottled: Mock<(until: Date | null) => void>;

    beforeEach(() => {
        vi.clearAllMocks();
        onThrottled = vi.fn<(until: Date | null) => void>();
    });

    it("posts the phone under the phone_verification key and returns success", async () => {
        mocks.post.mockResolvedValue({ success: true, message: "sent" });
        const { result } = renderHook(() => useSendPhoneVerification(onThrottled));

        let returned;
        await act(async () => {
            returned = await result.current.send(PHONE);
        });

        expect(returned).toBe(true);
        expect(mocks.transform).toHaveBeenCalled();
        expect(mocks.post).toHaveBeenCalledWith("/phone_verification");
    });

    it("shows a verification throttle toast on a 429 and returns undefined", async () => {
        mocks.post.mockRejectedValue({ response: { status: 429, headers: { "retry-after": "90" } } });
        const { result } = renderHook(() => useSendPhoneVerification(onThrottled));

        let returned;
        await act(async () => {
            returned = await result.current.send(PHONE);
        });

        expect(returned).toBeUndefined();
        expect(mocks.notify).toHaveBeenCalledWith({
            level: "error",
            title: "Too many verification attempts. Please wait 2 minutes before trying again.",
        });
        expect(onThrottled).toHaveBeenCalledWith(expect.any(Date));
    });

    // @lat: [[send-phone-verification-error-handling#Why a failed phone-verification send must not stay silent]]
    it("tells the reader when the send failed, and does not throttle on a non-429", async () => {
        mocks.post.mockRejectedValue({ response: { status: 500 } });
        const { result } = renderHook(() => useSendPhoneVerification(onThrottled));

        let returned;
        await act(async () => {
            returned = await result.current.send(PHONE);
        });

        expect(returned).toBeUndefined();
        expect(mocks.notify).toHaveBeenCalledWith({
            level: "error",
            title: "Could not send confirmation code. Please try again.",
        });
        expect(onThrottled).not.toHaveBeenCalled();
    });
});
