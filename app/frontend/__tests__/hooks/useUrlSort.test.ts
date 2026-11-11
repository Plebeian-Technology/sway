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

import { useUrlSort } from "app/frontend/hooks/useUrlSort";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

const OPTIONS = ["introduced_date_time_utc:desc", "introduced_date_time_utc:asc", "title:asc", "title:desc"] as const;

const CONFIG = {
    options: OPTIONS,
    defaultValue: "introduced_date_time_utc:desc" as (typeof OPTIONS)[number],
    only: ["bills", "bills_total"],
    resetParams: ["bills_page"],
    errorTitle: "Could not sort.",
    sortParam: "bills_sort",
    directionParam: "bills_direction",
    legacySortAliases: ["sort"],
    legacyDirectionAliases: ["direction"],
};

beforeEach(() => window.history.replaceState({}, "", "/bills"));
afterEach(() => routerGet.mockReset());

describe("useUrlSort", () => {
    it("reads the default when the URL carries no sort params", () => {
        const { result } = renderHook(() => useUrlSort(CONFIG));

        expect(result.current.value).toBe("introduced_date_time_utc:desc");
    });

    it("mirrors the server's direction fallback for a partial URL", () => {
        window.history.replaceState({}, "", "/bills?bills_sort=title");

        const { result } = renderHook(() => useUrlSort(CONFIG));

        expect(result.current.value).toBe("title:desc");
    });

    it("falls back to the default for a non-allowlisted column", () => {
        window.history.replaceState({}, "", "/bills?bills_sort=passwords&bills_direction=asc");

        const { result } = renderHook(() => useUrlSort(CONFIG));

        expect(result.current.value).toBe("introduced_date_time_utc:desc");
    });

    it("onChange writes sort+direction, drops reset params, and partial-reloads", () => {
        window.history.replaceState({}, "", "/bills?bills_page=3&categories=Police");

        const { result } = renderHook(() => useUrlSort(CONFIG));
        act(() => result.current.onChange("title:asc"));

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url, , options] = routerGet.mock.calls[0] as [string, unknown, unknown];
        const params = new URLSearchParams(url.split("?")[1]);
        expect(params.get("bills_sort")).toBe("title");
        expect(params.get("bills_direction")).toBe("asc");
        expect(isQueryParamCleared(params, "bills_page")).toBe(true);
        expect(stripClearedQueryParams(url)).not.toContain("bills_page=");
        // Params that have nothing to do with sorting stay put.
        expect(params.get("categories")).toBe("Police");
        expect(options).toMatchObject({
            preserveScroll: true,
            preserveState: true,
            only: ["bills", "bills_total"],
        });
    });

    it("onChange back to the default clears the sort params", () => {
        window.history.replaceState({}, "", "/bills?bills_sort=title&bills_direction=asc&bills_page=2");

        const { result } = renderHook(() => useUrlSort(CONFIG));
        act(() => result.current.onChange(CONFIG.defaultValue));

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url] = routerGet.mock.calls[0];
        expect(isQueryParamCleared(url as string, "bills_sort")).toBe(true);
        expect(isQueryParamCleared(url as string, "bills_direction")).toBe(true);
        expect(isQueryParamCleared(url as string, "bills_page")).toBe(true);
        expect(stripClearedQueryParams(url as string)).toBe("/bills");
    });

    describe("canonical parameter names and dual-reading", () => {
        const NAMESPACED_CONFIG = {
            ...CONFIG,
            sortParam: "bills_sort",
            directionParam: "bills_direction",
            legacySortAliases: ["sort"],
            legacyDirectionAliases: ["direction"],
        };

        it("reads canonical bills_sort and bills_direction", () => {
            window.history.replaceState({}, "", "/bills?bills_sort=title&bills_direction=asc");

            const { result } = renderHook(() => useUrlSort(NAMESPACED_CONFIG));

            expect(result.current.value).toBe("title:asc");
        });

        it("falls back to legacy sort and direction when canonical parameters are absent", () => {
            window.history.replaceState({}, "", "/bills?sort=title&direction=asc");

            const { result } = renderHook(() => useUrlSort(NAMESPACED_CONFIG));

            expect(result.current.value).toBe("title:asc");
        });

        it("gives precedence to canonical parameters when both canonical and legacy are present", () => {
            window.history.replaceState(
                {},
                "",
                "/bills?bills_sort=title&bills_direction=asc&sort=introduced_date_time_utc&direction=desc",
            );

            const { result } = renderHook(() => useUrlSort(NAMESPACED_CONFIG));

            expect(result.current.value).toBe("title:asc");
        });

        it("onChange writes canonical parameters and deletes legacy aliases", () => {
            window.history.replaceState({}, "", "/bills?sort=title&direction=desc&bills_page=2");

            const { result } = renderHook(() => useUrlSort(NAMESPACED_CONFIG));
            act(() => result.current.onChange("title:asc"));

            expect(routerGet).toHaveBeenCalledTimes(1);
            const [url] = routerGet.mock.calls[0] as [string, unknown, unknown];
            const params = new URLSearchParams(url.split("?")[1]);
            expect(params.get("bills_sort")).toBe("title");
            expect(params.get("bills_direction")).toBe("asc");
            expect(isQueryParamCleared(params, "sort")).toBe(true);
            expect(isQueryParamCleared(params, "direction")).toBe(true);
            expect(isQueryParamCleared(params, "bills_page")).toBe(true);
            expect(stripClearedQueryParams(url)).toBe("/bills?bills_sort=title&bills_direction=asc");
        });

        it("onChange back to default clears canonical parameters and deletes legacy aliases", () => {
            window.history.replaceState(
                {},
                "",
                "/bills?bills_sort=title&bills_direction=asc&sort=title&direction=asc&bills_page=2",
            );

            const { result } = renderHook(() => useUrlSort(NAMESPACED_CONFIG));
            act(() => result.current.onChange(NAMESPACED_CONFIG.defaultValue));

            expect(routerGet).toHaveBeenCalledTimes(1);
            const [url] = routerGet.mock.calls[0] as [string, unknown, unknown];
            expect(isQueryParamCleared(url as string, "bills_sort")).toBe(true);
            expect(isQueryParamCleared(url as string, "bills_direction")).toBe(true);
            expect(isQueryParamCleared(url as string, "sort")).toBe(true);
            expect(isQueryParamCleared(url as string, "direction")).toBe(true);
            expect(isQueryParamCleared(url as string, "bills_page")).toBe(true);
            expect(stripClearedQueryParams(url as string)).toBe("/bills");
        });
    });
});
