let mockIsOnlineState = true;

jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: mockIsOnlineState, lastChecked: new Date() }),
}));

const mockCacheGet = jest.fn(
    async (_swayLocaleId: number) => [] as { bill: Record<string, unknown>; cachedAt: number }[],
);
const mockCacheSet = jest.fn(async (_swayLocaleId: number, _bills: unknown[]) => {});
jest.mock("../../src/cache/billCache", () => ({
    get: (...args: unknown[]) => mockCacheGet(...(args as [number])),
    set: (...args: unknown[]) => mockCacheSet(...(args as [number, unknown[]])),
    clearOne: jest.fn(async () => {}),
    clear: jest.fn(async () => {}),
}));

// The return type is a loose record because this single fake apiClient.get
// answers more than one endpoint — the bills payload and the category list.
const mockGet = jest.fn(async (_path: string): Promise<Record<string, unknown>> => ({ bills: [] as unknown[] }));
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...(args as [string])),
    },
}));

import { act, renderHook, waitFor } from "@testing-library/react-native";
import { useBills, useBillCategories, clearCapturedCategories } from "../../src/hooks/useBills";

describe("useBills", () => {
    beforeEach(() => {
        mockIsOnlineState = true;
        mockCacheGet.mockReset();
        mockCacheSet.mockReset();
        mockGet.mockReset();
        clearCapturedCategories();
        mockCacheGet.mockResolvedValue([]);
        mockCacheSet.mockResolvedValue(undefined);
    });

    test("returns cached bills then refreshes from /bills", async () => {
        const cached = [{ bill: { id: 1, title: "Cached" }, cachedAt: 1 }];
        const fresh = [
            { id: 1, title: "Fresh 1" },
            { id: 2, title: "Fresh 2" },
        ];
        mockCacheGet.mockResolvedValue(cached);
        mockGet.mockResolvedValue({ bills: fresh });

        const { result } = renderHook(() => useBills(42));

        await waitFor(() => expect(result.current.data).toEqual(fresh));
        expect(mockCacheGet).toHaveBeenCalledWith(42);
        expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("/bills?sway_locale_id=42"));
        expect(mockCacheSet).toHaveBeenCalledWith(42, fresh);
    });

    test("offline: returns cache only and skips network", async () => {
        mockIsOnlineState = false;
        const cached = [{ bill: { id: 7, title: "Offline cached" }, cachedAt: 1 }];
        mockCacheGet.mockResolvedValue(cached);

        const { result } = renderHook(() => useBills(99));

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.data).toEqual([{ id: 7, title: "Offline cached" }]);
        expect(mockGet).not.toHaveBeenCalled();
    });

    test("exposes isOnline from reachability", async () => {
        mockIsOnlineState = false;
        const { result } = renderHook(() => useBills(1));
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.isOnline).toBe(false);
    });

    test("cumulative pagination: initializes page 1 and loads page 2 via loadMore", async () => {
        const page1Bills = [
            { id: 1, title: "Bill 1" },
            { id: 2, title: "Bill 2" },
        ];
        const page2Bills = [
            { id: 1, title: "Bill 1" },
            { id: 2, title: "Bill 2" },
            { id: 3, title: "Bill 3" },
            { id: 4, title: "Bill 4" },
        ];
        mockGet.mockImplementation(async (path: string) => {
            if (path.includes("page=2")) {
                return { bills: page2Bills, bills_total: 4, all_categories: ["Housing"] };
            }
            return { bills: page1Bills, bills_total: 4, all_categories: ["Housing"] };
        });

        const { result } = renderHook(() => useBills(42));

        await waitFor(() => expect(result.current.data).toEqual(page1Bills));
        expect(result.current.page).toBe(1);
        expect(result.current.billsTotal).toBe(4);
        expect(result.current.hasMore).toBe(true);
        expect(result.current.allCategories).toEqual(["Housing"]);

        await act(async () => {
            await result.current.loadMore();
        });

        expect(result.current.data).toEqual(page2Bills);
        expect(result.current.page).toBe(2);
        expect(result.current.hasMore).toBe(false);
        expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("page=2"));
    });

    test("concurrency guard: ignores duplicate loadMore calls while request is in flight", async () => {
        let resolveRequest!: (val: Record<string, unknown>) => void;
        mockGet.mockImplementation(async (path: string) => {
            if (path.includes("page=2")) {
                return new Promise((resolve) => {
                    resolveRequest = resolve;
                });
            }
            return { bills: [{ id: 1 }], bills_total: 10 };
        });

        const { result } = renderHook(() => useBills(42));
        await waitFor(() => expect(result.current.data).toHaveLength(1));

        let p1: Promise<void> | undefined;
        let p2: Promise<void> | undefined;
        act(() => {
            p1 = result.current.loadMore();
            p2 = result.current.loadMore(); // Duplicate call while in-flight
        });

        expect(result.current.loadingMore).toBe(true);
        act(() => {
            resolveRequest({ bills: [{ id: 1 }, { id: 2 }], bills_total: 10 });
        });
        await act(async () => {
            await Promise.all([p1, p2]);
        });

        const page2Calls = mockGet.mock.calls.filter((c) => (c[0] as string).includes("page=2"));
        expect(page2Calls).toHaveLength(1);
    });

    test("page error and retry: sets pageError on failure and allows retry of the same page", async () => {
        let attempts = 0;
        mockGet.mockImplementation(async (path: string) => {
            if (path.includes("page=2")) {
                attempts += 1;
                if (attempts === 1) {
                    throw new Error("Server error");
                }
                return { bills: [{ id: 1 }, { id: 2 }], bills_total: 2 };
            }
            return { bills: [{ id: 1 }], bills_total: 2 };
        });

        const { result } = renderHook(() => useBills(42));
        await waitFor(() => expect(result.current.data).toHaveLength(1));

        await act(async () => {
            await result.current.loadMore();
        });

        expect(result.current.pageError).toBeTruthy();
        expect(result.current.page).toBe(1); // Page does not advance on error

        // Retry loadMore
        await act(async () => {
            await result.current.loadMore();
        });

        expect(result.current.pageError).toBeNull();
        expect(result.current.page).toBe(2);
        expect(result.current.data).toHaveLength(2);
    });

    test("refresh resets page to 1", async () => {
        mockGet.mockImplementation(async (path: string) => {
            if (path.includes("page=2")) {
                return { bills: [{ id: 1 }, { id: 2 }], bills_total: 2 };
            }
            return { bills: [{ id: 1 }], bills_total: 2 };
        });

        const { result } = renderHook(() => useBills(42));
        await waitFor(() => expect(result.current.data).toHaveLength(1));

        await act(async () => {
            await result.current.loadMore();
        });
        expect(result.current.page).toBe(2);

        await act(async () => {
            await result.current.refresh();
        });
        expect(result.current.page).toBe(1);
    });

    test("eliminates duplicate category fetch by capturing all_categories from useBills", async () => {
        mockGet.mockResolvedValue({
            bills: [{ id: 1 }],
            bills_total: 1,
            all_categories: ["Environment", "Transit"],
        });

        // useBills fetches locale 88
        const billsHook = renderHook(() => useBills(88));
        await waitFor(() => expect(billsHook.result.current.data).toHaveLength(1));

        const getCallsBefore = mockGet.mock.calls.length;

        // useBillCategories is called for the same locale
        const catsHook = renderHook(() => useBillCategories(88));
        expect(catsHook.result.current.allCategories).toEqual(["Environment", "Transit"]);

        // No new HTTP requests were made!
        expect(mockGet.mock.calls.length).toBe(getCallsBefore);
    });

    test("past_bills_of_the_month mode fetches /past_bills_of_the_month and bypasses default locale billCache", async () => {
        const botmBills = [{ id: 50, title: "Featured Bill" }];
        mockGet.mockResolvedValue({
            bills: botmBills,
            bills_total: 1,
            list_mode: "past_bills_of_the_month",
        });

        const { result } = renderHook(() => useBills(42, { listMode: "past_bills_of_the_month" }));

        await waitFor(() => expect(result.current.data).toEqual(botmBills));
        expect(mockGet).toHaveBeenCalledWith("/past_bills_of_the_month?sway_locale_id=42&page=1");
        expect(mockCacheGet).not.toHaveBeenCalled();
        expect(mockCacheSet).not.toHaveBeenCalled();
    });

    test("all_bills mode with legislativeSessionId passes bills_legislative_session_id and exposes session metadata", async () => {
        const historicalBills = [{ id: 60, title: "2024 Historical Bill" }];
        const sessions = [
            { id: 10, name: "2026 Session", active: true },
            { id: 9, name: "2024 Session", active: false },
        ];
        mockGet.mockResolvedValue({
            bills: historicalBills,
            bills_total: 1,
            legislative_sessions: sessions,
            selected_legislative_session_id: 9,
        });

        const { result } = renderHook(() => useBills(42, { listMode: "all_bills", legislativeSessionId: 9 }));

        await waitFor(() => expect(result.current.data).toEqual(historicalBills));
        expect(mockGet).toHaveBeenCalledWith("/bills?sway_locale_id=42&page=1&bills_legislative_session_id=9");
        expect(result.current.legislativeSessions).toEqual(sessions);
        expect(result.current.selectedLegislativeSessionId).toBe(9);
        expect(mockCacheGet).not.toHaveBeenCalled();
        expect(mockCacheSet).not.toHaveBeenCalled();
    });

    test("switching locale resets legislativeSessions to the new locale while switching mode within a locale preserves them", async () => {
        const locale42Sessions = [{ id: 10, name: "Locale 42 Session", active: true }];
        mockGet
            .mockResolvedValueOnce({
                bills: [{ id: 1, title: "Bill 1" }],
                bills_total: 1,
                legislative_sessions: locale42Sessions,
            })
            .mockResolvedValueOnce({
                bills: [{ id: 2, title: "Past BOTM" }],
                bills_total: 1,
                legislative_sessions: [],
            })
            .mockResolvedValueOnce({
                bills: [{ id: 3, title: "Locale 99 Bill" }],
                bills_total: 1,
                legislative_sessions: [],
            });

        const { result, rerender } = renderHook(
            ({ localeId, mode }: { localeId: number; mode: "all_bills" | "past_bills_of_the_month" }) =>
                useBills(localeId, { listMode: mode }),
            { initialProps: { localeId: 42, mode: "all_bills" as const } },
        );

        await waitFor(() => expect(result.current.legislativeSessions).toEqual(locale42Sessions));

        rerender({ localeId: 42, mode: "past_bills_of_the_month" });
        await waitFor(() => expect(result.current.data).toEqual([{ id: 2, title: "Past BOTM" }]));
        expect(result.current.legislativeSessions).toEqual(locale42Sessions);

        rerender({ localeId: 99, mode: "all_bills" });
        expect(result.current.legislativeSessions).toEqual([]);
        await waitFor(() => expect(result.current.data).toEqual([{ id: 3, title: "Locale 99 Bill" }]));
    });
});

describe("useBillCategories", () => {
    beforeEach(() => {
        mockGet.mockReset();
    });

    test("maps res.all_categories to { allCategories } for the locale", async () => {
        mockGet.mockResolvedValue({ all_categories: ["Education", "Police"] });

        const { result } = renderHook(() => useBillCategories(7));

        await waitFor(() => expect(result.current.allCategories).toEqual(["Education", "Police"]));
        expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("/bills?sway_locale_id=7"));
    });

    test("falls back to [] when the response omits all_categories", async () => {
        mockGet.mockResolvedValue({});

        const { result } = renderHook(() => useBillCategories(7));

        await waitFor(() => expect(mockGet).toHaveBeenCalled());
        expect(result.current.allCategories).toEqual([]);
    });

    test("falls back to [] on fetch error", async () => {
        mockGet.mockRejectedValue(new Error("network down"));

        const { result } = renderHook(() => useBillCategories(7));

        await waitFor(() => expect(mockGet).toHaveBeenCalled());
        expect(result.current.allCategories).toEqual([]);
    });

    test("skips the fetch and returns [] when swayLocaleId is 0", () => {
        const { result } = renderHook(() => useBillCategories(0));

        expect(result.current.allCategories).toEqual([]);
        expect(mockGet).not.toHaveBeenCalled();
    });
});
