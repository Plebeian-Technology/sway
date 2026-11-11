// A delayed navigation from useSearchParams has to be called off when the
// component goes away. add and remove with debounceMs set a timer that calls
// router.get later. Without that cleanup, a component that disappears while the
// timer is still running would still send the visit.

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const routerGet = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({ router: { get: (...a: any[]) => routerGet(...a) } }));

import { useSearchParams } from "app/frontend/hooks/useSearchParams";

beforeEach(() => vi.useFakeTimers());
afterEach(() => {
    vi.useRealTimers();
    routerGet.mockReset();
});

describe("useSearchParams — debounced navigation cleanup", () => {
    it("cancels a pending debounced navigation on unmount", () => {
        const { result, unmount } = renderHook(() => useSearchParams());

        act(() => result.current.add("q", "x", { debounceMs: 300 }));
        unmount();
        const advanceResult = act(() => vi.advanceTimersByTime(400));
        if (advanceResult instanceof Promise) {
            advanceResult.catch(() => {});
        }

        expect(routerGet).not.toHaveBeenCalled();
    });

    it("fires the debounced navigation once when not unmounted", () => {
        const { result } = renderHook(() => useSearchParams());

        act(() => result.current.add("q", "x", { debounceMs: 300 }));
        expect(routerGet).not.toHaveBeenCalled(); // the wait is not over yet

        const advanceResult2 = act(() => vi.advanceTimersByTime(400));
        if (advanceResult2 instanceof Promise) {
            advanceResult2.catch(() => {});
        }
        expect(routerGet).toHaveBeenCalledTimes(1);
    });
});
