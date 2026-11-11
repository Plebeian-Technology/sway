import { renderHook, act } from "@testing-library/react";
import { useTwoTapConfirm } from "app/frontend/hooks/useTwoTapConfirm";

describe("useTwoTapConfirm", () => {
    beforeEach(() => vi.useFakeTimers());
    afterEach(() => vi.useRealTimers());

    it("starts un-armed: confirming === false", () => {
        const { result } = renderHook(() => useTwoTapConfirm());
        expect(result.current.confirming).toBe(false);
    });

    it("arm() flips confirming to true", () => {
        const { result } = renderHook(() => useTwoTapConfirm());
        act(() => result.current.arm());
        expect(result.current.confirming).toBe(true);
    });

    it("disarm() flips confirming back to false", () => {
        const { result } = renderHook(() => useTwoTapConfirm());
        act(() => result.current.arm());
        act(() => result.current.disarm());
        expect(result.current.confirming).toBe(false);
    });

    it("auto-disarms after timeoutMs (default 3000)", () => {
        const { result } = renderHook(() => useTwoTapConfirm());
        act(() => result.current.arm());
        expect(result.current.confirming).toBe(true);
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(3000));
        expect(result.current.confirming).toBe(false);
    });
});
