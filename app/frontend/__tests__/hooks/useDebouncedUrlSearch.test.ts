// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const routerGet = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({
    router: {
        get: (...a: unknown[]) => routerGet(...a),
        on: vi.fn<(type: string, callback: unknown) => () => void>(() => vi.fn<() => void>()),
    },
}));
const notified = vi.fn<(...args: unknown[]) => void>();
vi.mock("app/frontend/sway_utils", () => ({ notify: (...a: unknown[]) => notified(...a) }));

import { useDebouncedUrlSearch } from "app/frontend/hooks/useDebouncedUrlSearch";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

const CONFIG = {
    only: ["bills", "bills_total"],
    resetParams: ["bills_page"],
    errorTitle: "Could not search.",
    param: "bills_search",
    legacyAliases: ["search"],
    debounceMs: 350,
};

beforeEach(() => {
    vi.useFakeTimers();
    window.history.replaceState({}, "", "/bills");
});
afterEach(() => {
    vi.useRealTimers();
    routerGet.mockReset();
});

describe("useDebouncedUrlSearch", () => {
    it("exposes the committed URL value", () => {
        window.history.replaceState({}, "", "/bills?bills_search=police");

        const { result } = renderHook(() => useDebouncedUrlSearch(CONFIG));

        expect(result.current.value).toBe("police");
    });

    it("updates the draft value immediately but debounces the visit", () => {
        const { result } = renderHook(() => useDebouncedUrlSearch(CONFIG));

        act(() => result.current.onChange("hou"));
        expect(result.current.value).toBe("hou");
        expect(routerGet).not.toHaveBeenCalled();

        act(() => result.current.onChange("housing"));
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(400));

        // The two keystrokes fold into ONE visit, carrying the newest term.
        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url, , options] = routerGet.mock.calls[0];
        expect(new URLSearchParams((url as string).split("?")[1]).get("bills_search")).toBe("housing");
        expect(options).toMatchObject({
            preserveScroll: true,
            preserveState: true,
            only: ["bills", "bills_total"],
        });
        expect(options).not.toHaveProperty("reset");
    });

    it("passes reset option to router.get when configured", () => {
        const { result } = renderHook(() =>
            useDebouncedUrlSearch({
                ...CONFIG,
                param: "feed_search",
                resetParams: ["feed_cursor"],
                only: ["items", "feed_search"],
                reset: ["items"],
            }),
        );

        act(() => result.current.onChange("housing"));
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(400));

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [, , options] = routerGet.mock.calls[0];
        expect(options).toMatchObject({
            only: ["items", "feed_search"],
            reset: ["items"],
        });
    });

    it("trims the term, clears the param when blank, and drops reset params", () => {
        window.history.replaceState({}, "", "/bills?bills_search=police&bills_page=3");

        const { result } = renderHook(() => useDebouncedUrlSearch(CONFIG));
        act(() => result.current.onChange("   "));
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(400));

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url] = routerGet.mock.calls[0];
        expect(isQueryParamCleared(url as string, "bills_search")).toBe(true);
        expect(isQueryParamCleared(url as string, "bills_page")).toBe(true);
        expect(stripClearedQueryParams(url as string)).toBe("/bills");
    });

    it("cancels the pending visit on unmount", () => {
        const { result, unmount } = renderHook(() => useDebouncedUrlSearch(CONFIG));

        act(() => result.current.onChange("police"));
        unmount();
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(400));

        expect(routerGet).not.toHaveBeenCalled();
    });

    it("drops the draft once the URL echoes it back, then follows external URL changes", () => {
        const { result, rerender } = renderHook(() => useDebouncedUrlSearch(CONFIG));

        act(() => result.current.onChange("police"));
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(400));

        // Pretend Inertia finished the visit we asked for: the URL now carries
        // the term, so on the next render the hook throws the draft away...
        window.history.replaceState({}, "", "/bills?bills_search=police");
        rerender();
        expect(result.current.value).toBe("police");

        // ...so a later change from OUTSIDE, such as browser Back, is followed.
        window.history.replaceState({}, "", "/bills");
        rerender();
        expect(result.current.value).toBe("");
    });

    describe("dual-reading and legacy aliases (Move the Legislators page's parameters onto its own namespace)", () => {
        const NAMESPACED_CONFIG = {
            only: ["legislators"],
            errorTitle: "Could not filter legislators.",
            param: "legislators_search",
            legacyAliases: ["search"],
            debounceMs: 350,
        };

        it("reads canonical param when present in URL", () => {
            window.history.replaceState({}, "", "/legislators?legislators_search=smith");
            const { result } = renderHook(() => useDebouncedUrlSearch(NAMESPACED_CONFIG));
            expect(result.current.value).toBe("smith");
        });

        it("falls back to legacy alias when canonical param is absent", () => {
            window.history.replaceState({}, "", "/legislators?search=smith");
            const { result } = renderHook(() => useDebouncedUrlSearch(NAMESPACED_CONFIG));
            expect(result.current.value).toBe("smith");
        });

        it("gives precedence to canonical param when both canonical and legacy alias are present", () => {
            window.history.replaceState({}, "", "/legislators?legislators_search=smith&search=jones");
            const { result } = renderHook(() => useDebouncedUrlSearch(NAMESPACED_CONFIG));
            expect(result.current.value).toBe("smith");
        });

        it("writes canonical param and clears legacy alias on search change", async () => {
            window.history.replaceState({}, "", "/legislators?search=jones");
            const { result } = renderHook(() => useDebouncedUrlSearch(NAMESPACED_CONFIG));

            act(() => result.current.onChange("smith"));
            await act(async () => {
                vi.advanceTimersByTime(400);
            });

            expect(routerGet).toHaveBeenCalledTimes(1);
            const [url] = routerGet.mock.calls[0];
            const searchParams = new URLSearchParams((url as string).split("?")[1]);
            expect(searchParams.get("legislators_search")).toBe("smith");
            expect(isQueryParamCleared(searchParams, "search")).toBe(true);
            expect(stripClearedQueryParams(url as string)).toBe("/legislators?legislators_search=smith");
        });

        it("clears both canonical param and legacy alias when term is cleared", async () => {
            window.history.replaceState({}, "", "/legislators?legislators_search=smith&search=jones");
            const { result } = renderHook(() => useDebouncedUrlSearch(NAMESPACED_CONFIG));

            act(() => result.current.onChange("   "));
            await act(async () => {
                vi.advanceTimersByTime(400);
            });

            expect(routerGet).toHaveBeenCalledTimes(1);
            const [url] = routerGet.mock.calls[0];
            expect(isQueryParamCleared(url as string, "legislators_search")).toBe(true);
            expect(isQueryParamCleared(url as string, "search")).toBe(true);
            expect(stripClearedQueryParams(url as string)).toBe("/legislators");
        });
    });
});
