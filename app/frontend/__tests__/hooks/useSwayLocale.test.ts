import { renderHook, act } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach } from "vitest";

const routerGet = vi.fn<(...args: unknown[]) => void>();
const routerFlushAll = vi.fn<() => void>();
const notify = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: { sway_locale: { id: number; name: string } } }>(() => ({
        props: { sway_locale: { id: 1, name: "baltimore-maryland-united_states" } },
    })),
    router: {
        get: (...args: unknown[]) => routerGet(...args),
        flushAll: () => routerFlushAll(),
    },
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notify(...args),
}));

import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

type VisitOptions = {
    only?: string[];
    preserveState?: boolean;
    preserveScroll?: boolean;
    replace?: boolean;
    onStart?: () => void;
    onFinish?: () => void;
    onError?: (errors: Record<string, string>) => void;
};

const lastVisit = () => {
    const call = routerGet.mock.calls.at(-1);
    const url = new URL(call?.[0] as string, window.location.origin);
    return {
        path: url.pathname,
        params: url.searchParams,
        data: call?.[1] as Record<string, string>,
        options: call?.[2] as VisitOptions,
    };
};

const switchTo = (swayLocaleId: number, refreshProps?: string[]) => {
    const { result } = renderHook(() => useSwayLocale(refreshProps));
    act(() => result.current[1](swayLocaleId));
};

describe("useSwayLocale — switching locale", () => {
    beforeEach(() => {
        routerGet.mockReset();
        routerFlushAll.mockReset();
        notify.mockReset();
        window.history.replaceState({}, "", "/bills?search=zoning&tab=history");
    });

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    describe("when the server refuses the switch", () => {
        it("tells the reader instead of failing silently", () => {
            switchTo(3);

            act(() => lastVisit().options.onError?.({}));

            expect(notify).toHaveBeenCalledWith(expect.objectContaining({ level: "error" }));
        });

        // The page still has to undo anything it did on the assumption that the
        // switch would work. Legislators, for one, labels its History entries
        // with the incoming jurisdiction before the answer comes back (see
        // LegislatorsHistoryLocale.test.tsx).
        it("hands the failure to the caller so the page can roll back", () => {
            const { result } = renderHook(() => useSwayLocale());
            const onError = vi.fn<() => void>();
            act(() => result.current[1](3, { onError }));

            act(() => lastVisit().options.onError?.({}));

            expect(onError).toHaveBeenCalledTimes(1);
        });

        it("does not notify or call back on a switch that lands", () => {
            const { result } = renderHook(() => useSwayLocale());
            const onError = vi.fn<() => void>();
            act(() => result.current[1](3, { onError }));

            act(() => lastVisit().options.onFinish?.());

            expect(notify).not.toHaveBeenCalled();
            expect(onError).not.toHaveBeenCalled();
        });
    });

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    describe("what the picker should display", () => {
        it("reports the chosen locale while the switch is in flight", () => {
            const { result } = renderHook(() => useSwayLocale());
            act(() => result.current[1](3));

            act(() => lastVisit().options.onStart?.());

            expect(result.current[2]).toBe(3);
        });

        it("hands back to the server's locale once the switch settles", () => {
            const { result } = renderHook(() => useSwayLocale());
            act(() => result.current[1](3));

            act(() => lastVisit().options.onStart?.());
            act(() => lastVisit().options.onFinish?.());

            expect(result.current[2]).toBeUndefined();
        });

        // onFinish also runs when the visit fails, so the control falls back to
        // the jurisdiction still in force, rather than showing a switch that
        // never happened.
        it("stops claiming a locale the switch failed to reach", () => {
            const { result } = renderHook(() => useSwayLocale());
            act(() => result.current[1](3));

            act(() => lastVisit().options.onStart?.());
            expect(result.current[2]).toBe(3);

            act(() => lastVisit().options.onFinish?.());

            expect(result.current[2]).toBeUndefined();
        });
    });

    it("carries the page's existing query string through the switch", () => {
        switchTo(3);

        expect(lastVisit().path).toBe("/bills");
        expect(Object.fromEntries(lastVisit().params)).toEqual({
            search: "zoning",
            tab: "history",
            sway_locale_id: "3",
        });
        expect(lastVisit().data).toEqual({});
    });

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    it("drops the page window, which means nothing in another jurisdiction", () => {
        window.history.replaceState({}, "", "/bills?search=zoning&page=5&bills_page=2");

        switchTo(3);

        const params = lastVisit().params;
        expect(params.get("search")).toBe("zoning");
        expect(params.get("sway_locale_id")).toBe("3");
        expect(isQueryParamCleared(params, "page")).toBe(true);
        expect(isQueryParamCleared(params, "bills_page")).toBe(true);
        const stripped = stripClearedQueryParams(params);
        expect(stripped.has("page")).toBe(false);
        expect(stripped.has("bills_page")).toBe(false);
        expect(Object.fromEntries(stripped)).toEqual({ search: "zoning", sway_locale_id: "3" });
    });

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    describe("when the page declares the props its switch refreshes", () => {
        const REFRESH_PROPS = ["bills", "bills_total", "sway_locale"];

        it("requests exactly those props", () => {
            switchTo(3, REFRESH_PROPS);

            expect(lastVisit().options.only).toEqual(REFRESH_PROPS);
        });

        it("preserves component state, so the page is not torn down and rebuilt", () => {
            switchTo(3, REFRESH_PROPS);

            expect(lastVisit().options.preserveState).toBe(true);
        });
    });

    // Listing those props means knowing every single prop that depends on the
    // locale. A page that has not checked its own must keep the full visit,
    // which rebuilds everything, rather than quietly showing the old locale's
    // data under the new locale's name.
    describe("when the page declares nothing", () => {
        it("makes a full visit", () => {
            switchTo(3);

            expect(lastVisit().options.only).toBeUndefined();
        });

        it("does not preserve component state", () => {
            switchTo(3);

            expect(lastVisit().options.preserveState).toBe(false);
        });
    });

    // A different jurisdiction means different content, so a scroll position
    // measured against the old locale's list means nothing in the new one. Both
    // paths let Inertia send the reader back to the top. That is a deliberate
    // call by the project owner.
    describe("scroll position", () => {
        it("is not held, whether or not the page declares props", () => {
            switchTo(3, ["bills"]);
            expect(lastVisit().options.preserveScroll).toBeUndefined();

            switchTo(3);
            expect(lastVisit().options.preserveScroll).toBeUndefined();
        });
    });

    it("flushes the Inertia prefetch cache before issuing the navigation request", () => {
        switchTo(3);

        expect(routerFlushAll).toHaveBeenCalledTimes(1);
        expect(routerGet).toHaveBeenCalledTimes(1);
        const flushOrder = routerFlushAll.mock.invocationCallOrder[0];
        const getOrder = routerGet.mock.invocationCallOrder[0];
        expect(flushOrder).toBeLessThan(getOrder);
    });
});
