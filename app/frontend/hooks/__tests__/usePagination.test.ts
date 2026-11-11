import { act, renderHook } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { usePagination } from "app/frontend/hooks/usePagination";
// oxlint-disable-next-line import/default -- Vite ?raw import returns the file as a string; the underlying module has no default export to check.
import usePaginationSource from "app/frontend/hooks/usePagination.ts?raw";

describe("usePagination", () => {
    it("respects the given page size", () => {
        const items = Array.from({ length: 7 }, (_, i) => i);
        const { result } = renderHook(() => usePagination(items, 3));
        expect(result.current.pageItems).toEqual([0, 1, 2]);
        expect(result.current.pageCount).toBe(3);
    });

    it("pages forward with goToNext", () => {
        const items = Array.from({ length: 7 }, (_, i) => i);
        const { result } = renderHook(() => usePagination(items, 3));
        act(() => result.current.goToNext());
        expect(result.current.page).toBe(2);
        expect(result.current.pageItems).toEqual([3, 4, 5]);
    });

    it("pages backward with goToPrevious", () => {
        const items = Array.from({ length: 7 }, (_, i) => i);
        const { result } = renderHook(() => usePagination(items, 3));
        act(() => result.current.goToNext());
        act(() => result.current.goToPrevious());
        expect(result.current.page).toBe(1);
        expect(result.current.pageItems).toEqual([0, 1, 2]);
    });

    it("goToPage jumps directly and clamps out-of-range targets to the valid range", () => {
        const items = Array.from({ length: 7 }, (_, i) => i);
        const { result } = renderHook(() => usePagination(items, 3));

        act(() => result.current.goToPage(3));
        expect(result.current.page).toBe(3);
        expect(result.current.pageItems).toEqual([6]);

        act(() => result.current.goToPage(99));
        expect(result.current.page).toBe(3);

        act(() => result.current.goToPage(0));
        expect(result.current.page).toBe(1);
    });

    it("reports hasPrevious/hasNext at each boundary", () => {
        const items = Array.from({ length: 7 }, (_, i) => i);
        const { result } = renderHook(() => usePagination(items, 3));
        expect(result.current.hasPrevious).toBe(false);
        expect(result.current.hasNext).toBe(true);

        act(() => result.current.goToPage(2));
        expect(result.current.hasPrevious).toBe(true);
        expect(result.current.hasNext).toBe(true);

        act(() => result.current.goToPage(3));
        expect(result.current.hasPrevious).toBe(true);
        expect(result.current.hasNext).toBe(false);
    });

    it("goToNext at the last page and goToPrevious at the first page are no-ops", () => {
        const items = Array.from({ length: 7 }, (_, i) => i);
        const { result } = renderHook(() => usePagination(items, 3));
        act(() => result.current.goToPrevious());
        expect(result.current.page).toBe(1);

        act(() => result.current.goToPage(3));
        act(() => result.current.goToNext());
        expect(result.current.page).toBe(3);
    });

    it("resets to page 1 when the collection shrinks out from under the current page", () => {
        const { result, rerender } = renderHook(({ items }) => usePagination(items, 5), {
            initialProps: { items: Array.from({ length: 10 }, (_, i) => i) },
        });

        act(() => result.current.goToPage(2));
        expect(result.current.page).toBe(2);
        expect(result.current.pageItems).toEqual([5, 6, 7, 8, 9]);

        rerender({ items: [0, 1, 2] });

        expect(result.current.page).toBe(1);
        expect(result.current.pageCount).toBe(1);
        expect(result.current.pageItems).toEqual([0, 1, 2]);
    });

    it("stays on the current page when the collection shrinks but the page is still valid", () => {
        const { result, rerender } = renderHook(({ items }) => usePagination(items, 5), {
            initialProps: { items: Array.from({ length: 20 }, (_, i) => i) },
        });

        act(() => result.current.goToPage(2));
        rerender({ items: Array.from({ length: 12 }, (_, i) => i) });

        expect(result.current.page).toBe(2);
        expect(result.current.pageItems).toEqual([5, 6, 7, 8, 9]);
    });

    it("treats an empty collection as a single, empty page", () => {
        const { result } = renderHook(() => usePagination([], 5));
        expect(result.current.pageCount).toBe(1);
        expect(result.current.page).toBe(1);
        expect(result.current.pageItems).toEqual([]);
        expect(result.current.hasPrevious).toBe(false);
        expect(result.current.hasNext).toBe(false);
    });

    it("treats a collection smaller than one page as a single page", () => {
        const { result } = renderHook(() => usePagination([1, 2], 5));
        expect(result.current.pageCount).toBe(1);
        expect(result.current.pageItems).toEqual([1, 2]);
        expect(result.current.hasPrevious).toBe(false);
        expect(result.current.hasNext).toBe(false);
    });

    it("uses no useEffect (the page is clamped during render, not in an effect)", () => {
        expect(usePaginationSource).not.toMatch(/useEffect\(/);
    });
});
