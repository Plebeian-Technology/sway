// @lat: [[activity-log-stream#Why the URL param list includes the cursor]]

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

let currentProps: Record<string, unknown> = {};
const usePageMock = vi.fn<() => { props: Record<string, unknown> }>();
usePageMock.mockImplementation(() => ({ props: currentProps }));
let lastGetOptions:
    | (Record<string, unknown> & {
          onSuccess?: (obj: Record<string, unknown>) => void;
          onStart?: () => void;
          onError?: (errors: Record<string, string>) => void;
          onFinish?: () => void;
      })
    | null = null;
const routerGet = vi.fn<(url: string, params: unknown, options: Record<string, unknown>) => void>();
routerGet.mockImplementation((_url: string, _params: unknown, options: Record<string, unknown>) => {
    lastGetOptions = options;
});
vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: { get: (url: string, params: unknown, options: any) => routerGet(url, params, options) },
}));

let capturedOnAppend: ((e: any) => void) | null = null;
vi.mock("app/frontend/channels/activityLogChannel", () => ({
    subscribeActivityLog: (_id: string, cb: (e: any) => void) => {
        capturedOnAppend = cb;
        return () => {};
    },
}));

import { useActivityLogStream } from "app/frontend/components/admin/creator/activity-log/useActivityLogStream";

const entry = (id: string) => ({ id }) as any;
const entries = (ids: string[]) => ids.map(entry);
const setProps = (list: any[], cursor: string | null, hasMore: boolean) => {
    currentProps = {
        activity_log_entries: list,
        activity_log_next_cursor: cursor,
        activity_log_has_more: hasMore,
    };
};
const pageIds = (result: { current: { pageEntries: any[] } }) => result.current.pageEntries.map((e) => e.id);

beforeEach(() => {
    currentProps = {};
    lastGetOptions = null;
    capturedOnAppend = null;
});
afterEach(() => vi.clearAllMocks());

describe("useActivityLogStream — ten-per-page numbered paging", () => {
    it("shows only the first ten entries on page 1, out of a larger fetched batch", () => {
        setProps(entries(["A", "B", "C"]), null, false);
        const { result } = renderHook(() => useActivityLogStream(null));

        expect(pageIds(result)).toEqual(["A", "B", "C"]);
        expect(result.current.page).toBe(1);
        expect(result.current.pageCount).toBe(1);
    });

    it("goToPage REPLACES the visible entries with the target page, not appends to them", () => {
        setProps(entries(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10", "e11", "e12"]), null, false);
        const { result } = renderHook(() => useActivityLogStream(null));

        expect(pageIds(result)).toEqual(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10"]);
        expect(result.current.pageCount).toBe(2);

        act(() => result.current.goToPage(2));

        expect(pageIds(result)).toEqual(["e11", "e12"]);
    });

    it("goToPage clamps to the known page count rather than fetching ahead", () => {
        setProps(entries(["A", "B"]), "cur1", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.goToPage(9));

        expect(result.current.page).toBe(1);
        expect(routerGet).not.toHaveBeenCalled();
    });

    it("handleLoadMore extends the buffer, keeping earlier pages intact alongside the new batch", () => {
        setProps(entries(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10"]), "cur1", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.goToPage(1));
        act(() => result.current.handleLoadMore());

        act(() => {
            setProps(entries(["e11", "e12"]), null, false);
            rerender();
        });
        act(() => {
            lastGetOptions?.onSuccess?.({
                props: {
                    activity_log_entries: entries(["e11", "e12"]),
                    activity_log_next_cursor: null,
                    activity_log_has_more: false,
                },
            });
            lastGetOptions?.onFinish?.();
        });

        expect(pageIds(result)).toEqual(["e11", "e12"]);
        act(() => result.current.goToPage(1));
        expect(pageIds(result)).toEqual(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10"]);
    });

    it("onFilterChange replaces the buffer and resets an operator on page 2 back to page 1", () => {
        setProps(entries(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10", "e11"]), "cur1", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.goToPage(2));
        expect(result.current.page).toBe(2);

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        act(() => {
            setProps(entries(["X"]), null, false);
            rerender();
        });

        expect(pageIds(result)).toEqual(["X"]);
        expect(result.current.page).toBe(1);
    });
});

describe("useActivityLogStream — live entries queue instead of reshuffling a page", () => {
    it("a live entry does not appear on the current page, on page 1 or any other page", () => {
        setProps(entries(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10", "e11"]), null, false);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.goToPage(2));
        const before = pageIds(result);

        act(() => capturedOnAppend?.(entry("live1")));

        expect(pageIds(result)).toEqual(before);
        expect(result.current.pendingLiveCount).toBe(1);
    });

    it("showPendingLiveEntries merges the queue onto page 1 and clears the queue", () => {
        setProps(entries(["e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "e10", "e11"]), null, false);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.goToPage(2));
        act(() => capturedOnAppend?.(entry("live1")));
        expect(result.current.page).toBe(2);

        act(() => result.current.showPendingLiveEntries());

        expect(result.current.page).toBe(1);
        expect(result.current.pendingLiveCount).toBe(0);
        expect(pageIds(result)[0]).toBe("live1");
    });

    // @lat: [[activity-log-stream#Where a load-more lands, and why it is not the next page]]
    it("lands on the page holding the first new entry when live entries left the buffer off a page boundary", () => {
        const fetched = Array.from({ length: 10 }, (_, i) => `e${i + 1}`);
        setProps(entries(fetched), "cur1", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => capturedOnAppend?.(entry("live1")));
        act(() => capturedOnAppend?.(entry("live2")));
        act(() => capturedOnAppend?.(entry("live3")));
        act(() => result.current.showPendingLiveEntries());
        expect(result.current.pageCount).toBe(2);

        act(() => result.current.goToPage(2));
        act(() => result.current.handleLoadMore());

        const older = Array.from({ length: 50 }, (_, i) => `o${i + 1}`);
        act(() => {
            setProps(entries(older), null, false);
            rerender();
        });
        act(() => {
            lastGetOptions?.onSuccess?.({
                props: {
                    activity_log_entries: entries(older),
                    activity_log_next_cursor: null,
                    activity_log_has_more: false,
                },
            });
            lastGetOptions?.onFinish?.();
        });

        expect(pageIds(result)).toContain("o1");
    });

    // @lat: [[activity-log-stream#The page number is clamped where it is read]]
    it("never strands the operator past the last page when a fetch adds nothing new", () => {
        const fetched = Array.from({ length: 10 }, (_, i) => `e${i + 1}`);
        setProps(entries(fetched), "cur1", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.handleLoadMore());
        act(() => {
            setProps(entries(fetched), null, false);
            rerender();
        });
        act(() => {
            lastGetOptions?.onSuccess?.({
                props: {
                    activity_log_entries: entries(fetched),
                    activity_log_next_cursor: null,
                    activity_log_has_more: false,
                },
            });
            lastGetOptions?.onFinish?.();
        });

        expect(result.current.page).toBe(result.current.pageCount);
        expect(pageIds(result)).toEqual(fetched);
    });

    it("does not queue a duplicate of an entry already on the page", () => {
        setProps(entries(["e1"]), null, false);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => capturedOnAppend?.(entry("e1")));

        expect(result.current.pendingLiveCount).toBe(0);
    });
});

// @lat: [[activity-log-stream#Why the URL param list includes the cursor]]
describe("useActivityLogStream — the address the visits are sent to", () => {
    const at = (address: string) => window.history.replaceState({}, "", address);

    afterEach(() => at("/"));

    it("keeps the run pin through a filter change", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77&sway_locale_id=3");
        setProps(entries(["A"]), "cur1", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => {
            result.current.onFilterChange({ subject: "hearings" });
        });

        const url = routerGet.mock.calls[0][0];
        expect(url).toContain("run_id=77");
        expect(url).toContain("sway_locale_id=3");
        expect(url).toMatch(/^\/admin\/bill_creator\/12\/pipeline\?/);
    });

    it("keeps the run pin through a load-more click", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77");
        setProps(entries(["A"]), "cur1", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => {
            result.current.handleLoadMore();
        });

        expect(routerGet.mock.calls[0][0]).toContain("run_id=77");
    });

    it("drops a stale paging cursor when the filter changes", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77&cursor=abc123");
        setProps(entries(["A"]), "cur1", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => {
            result.current.onFilterChange({ subject: "hearings" });
        });

        const url = routerGet.mock.calls[0][0];
        expect(isQueryParamCleared(url, "cursor")).toBe(true);
        expect(stripClearedQueryParams(url)).not.toContain("cursor");
        expect(url).toContain("run_id=77");
    });

    // @lat: [[activity-log-stream#Why the URL param list includes the cursor]]
    it("sets the filters from the visit's data, not from what the address held", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77&severity=errors");
        setProps(entries(["A"]), "cur1", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => {
            result.current.onFilterChange({ subject: "hearings" });
        });

        const url = routerGet.mock.calls[0][0];
        expect(isQueryParamCleared(url, "severity")).toBe(true);
        expect(stripClearedQueryParams(url)).not.toContain("severity");
        expect(routerGet.mock.calls[0][1]).toEqual({ subject: "hearings" });
    });
});

describe("useActivityLogStream — a load-more clicked during a filter change", () => {
    const at = (address: string) => window.history.replaceState({}, "", address);

    afterEach(() => at("/"));

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    const landFilterChange = (
        options: typeof lastGetOptions,
        rerender: () => void,
        list: any[],
        cursor: string | null,
    ) => {
        at("/admin/bill_creator/12/pipeline?subject=hearings");
        setProps(list, cursor, true);
        act(() => rerender());
        act(() => {
            options?.onSuccess?.({
                props: {
                    activity_log_entries: list,
                    activity_log_next_cursor: cursor,
                    activity_log_has_more: true,
                },
            });
            options?.onFinish?.();
        });
    };

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    it("sends nothing while the filter change is still in flight", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["A"]), "old-filter-cursor", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        expect(routerGet).toHaveBeenCalledTimes(1);

        act(() => result.current.handleLoadMore());

        expect(routerGet).toHaveBeenCalledTimes(1);
    });

    it("fetches older entries under the new filter once the filter change lands", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["A"]), "old-filter-cursor", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        const filterVisit = lastGetOptions;
        act(() => result.current.handleLoadMore());

        landFilterChange(filterVisit, rerender, entries(["N1"]), "new-filter-cursor");

        expect(routerGet).toHaveBeenCalledTimes(2);
        expect(routerGet.mock.calls[1][1]).toEqual({ subject: "hearings", cursor: "new-filter-cursor" });
    });

    it("appends onto the new filter's entries, never the ones it replaced", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["OLD1", "OLD2"]), "old-filter-cursor", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        const filterVisit = lastGetOptions;
        act(() => result.current.handleLoadMore());

        landFilterChange(filterVisit, rerender, entries(["N1"]), "new-filter-cursor");

        act(() => {
            lastGetOptions?.onSuccess?.({
                props: {
                    activity_log_entries: entries(["N2"]),
                    activity_log_next_cursor: null,
                    activity_log_has_more: false,
                },
            });
        });

        expect(pageIds(result)).toEqual(["N1", "N2"]);
    });

    // @lat: [[activity-log-stream#Why a load-more waits for a filter change]]
    it("releases the held click against the entries that remain when the filter change fails", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["A"]), "old-filter-cursor", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        const filterVisit = lastGetOptions;
        act(() => result.current.handleLoadMore());
        expect(routerGet).toHaveBeenCalledTimes(1);

        act(() => {
            filterVisit?.onError?.({ subject: "is not a filter" });
            filterVisit?.onFinish?.();
        });

        // The list never changed, so the click is served from the cursor and
        // the filters that are still in effect.
        expect(routerGet).toHaveBeenCalledTimes(2);
        expect(routerGet.mock.calls[1][1]).toEqual({ severity: "errors", cursor: "old-filter-cursor" });
    });

    it("does not fire a held click twice when the filter change succeeds", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["A"]), "old-filter-cursor", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        const filterVisit = lastGetOptions;
        act(() => result.current.handleLoadMore());

        landFilterChange(filterVisit, rerender, entries(["N1"]), "new-filter-cursor");
        act(() => filterVisit?.onError?.({ subject: "too late" }));

        expect(routerGet).toHaveBeenCalledTimes(2);
    });

    it("keeps the click held for the newer filter change when one supersedes another", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["A"]), "old-filter-cursor", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        const firstVisit = lastGetOptions;
        act(() => result.current.onFilterChange({ subject: "runs" }));
        act(() => result.current.handleLoadMore());
        expect(routerGet).toHaveBeenCalledTimes(2);

        // The superseded visit finishing must not make the second one look settled.
        act(() => firstVisit?.onFinish?.());
        act(() => result.current.handleLoadMore());

        expect(routerGet).toHaveBeenCalledTimes(2);
    });

    it("still sends the load-more straight away when no filter change is in flight", () => {
        at("/admin/bill_creator/12/pipeline");
        setProps(entries(["A"]), "cur1", true);
        const { result } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.handleLoadMore());

        expect(routerGet).toHaveBeenCalledTimes(1);
        expect(routerGet.mock.calls[0][1]).toEqual({ cursor: "cur1" });
    });

    it("does not hold a click made after the filter change has settled", () => {
        at("/admin/bill_creator/12/pipeline?severity=errors");
        setProps(entries(["A"]), "old-filter-cursor", true);
        const { result, rerender } = renderHook(() => useActivityLogStream(null));

        act(() => result.current.onFilterChange({ subject: "hearings" }));
        const filterVisit = lastGetOptions;
        landFilterChange(filterVisit, rerender, entries(["N1"]), "new-filter-cursor");
        expect(routerGet).toHaveBeenCalledTimes(1);

        act(() => result.current.handleLoadMore());

        expect(routerGet).toHaveBeenCalledTimes(2);
        expect(routerGet.mock.calls[1][1]).toEqual({ subject: "hearings", cursor: "new-filter-cursor" });
    });
});
