/**
 * Empirical Stress Test Harness for Page the native mobile bills list
 *
 * Verifies the 5 challenge targets:
 * 1. Rapid multiple onEndReached triggers (concurrency lock verification)
 * 2. Stale response rejection on quick locale switching
 * 3. Offline transitions: does offline cache serve bills correctly?
 * 4. Page error retry: does clicking retry re-trigger the failed page?
 * 5. Filter / search empty state: does the server expansion button appear and function?
 */

let mockIsOnlineState = true;

jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({
        isOnline: mockIsOnlineState,
        isResolved: true,
        lastChecked: new Date(),
    }),
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

const mockGet = jest.fn(async (_path: string): Promise<Record<string, unknown>> => ({ bills: [] as unknown[] }));
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...(args as [string])),
    },
}));

// Mocks for UI components needed by BillsListScreen
jest.mock("../../src/components/SkeletonCard", () => {
    const ReactMod = require("react");
    const RNMod = require("react-native");
    return {
        SkeletonCard: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
        default: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
    };
});

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

jest.mock("../../src/components/BillCard", () => {
    const ReactMod = require("react");
    const RNMod = require("react-native");
    return {
        BillCard: ({ bill, testID }: { bill: { id: number; title: string }; testID?: string }) =>
            ReactMod.createElement(
                RNMod.View,
                { testID: testID ?? `bill-card-${bill.id}` },
                ReactMod.createElement(RNMod.Text, null, bill.title),
            ),
        default: ({ bill, testID }: { bill: { id: number; title: string }; testID?: string }) =>
            ReactMod.createElement(
                RNMod.View,
                { testID: testID ?? `bill-card-${bill.id}` },
                ReactMod.createElement(RNMod.Text, null, bill.title),
            ),
    };
});

jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

import React from "react";
import { act, fireEvent, render, renderHook, screen, waitFor } from "@testing-library/react-native";
import { useBills, clearCapturedCategories, type UseBillsResult } from "../../src/hooks/useBills";
import BillsListScreen from "../../src/screens/BillsListScreen";

const LOCALES = [
    { id: 1, name: "Baltimore" },
    { id: 2, name: "Maryland" },
];

const BASE_BOOTSTRAP = {
    locale: { id: 1, name: "baltimore-maryland-united_states" },
    sway_locales: LOCALES,
};

function makeNav() {
    return { navigate: jest.fn() };
}

describe("Empirical Challenge: Page the native mobile bills list Stress Suite", () => {
    beforeEach(() => {
        mockIsOnlineState = true;
        mockCacheGet.mockReset();
        mockCacheSet.mockReset();
        mockGet.mockReset();
        mockUseBootstrap.mockReset();
        clearCapturedCategories();

        mockCacheGet.mockResolvedValue([]);
        mockCacheSet.mockResolvedValue(undefined);
        mockUseBootstrap.mockReturnValue({
            bootstrap: BASE_BOOTSTRAP,
            loading: false,
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Target 1: Rapid multiple onEndReached triggers (concurrency lock verification)
    // ─────────────────────────────────────────────────────────────────────────
    describe("Target 1: Rapid onEndReached concurrency lock", () => {
        test("burst of 50 simultaneous loadMore calls triggers exactly ONE network request for page 2", async () => {
            let resolvePage2!: (val: Record<string, unknown>) => void;
            mockGet.mockImplementation(async (path: string) => {
                if (path.includes("page=2")) {
                    return new Promise((resolve) => {
                        resolvePage2 = resolve;
                    });
                }
                return {
                    bills: Array.from({ length: 24 }, (_, i) => ({ id: i + 1, title: `Bill ${i + 1}` })),
                    bills_total: 100,
                    all_categories: ["Housing"],
                };
            });

            const { result } = renderHook(() => useBills(1));
            await waitFor(() => expect(result.current.data).toHaveLength(24));
            expect(result.current.page).toBe(1);
            expect(result.current.hasMore).toBe(true);

            // Fire a burst of 50 simultaneous loadMore calls
            const promises: Promise<void>[] = [];
            act(() => {
                for (let i = 0; i < 50; i++) {
                    promises.push(result.current.loadMore());
                }
            });

            expect(result.current.loadingMore).toBe(true);

            // Resolve the in-flight page 2 request
            act(() => {
                resolvePage2({
                    bills: Array.from({ length: 48 }, (_, i) => ({ id: i + 1, title: `Bill ${i + 1}` })),
                    bills_total: 100,
                });
            });

            await act(async () => {
                await Promise.all(promises);
            });

            expect(result.current.loadingMore).toBe(false);
            expect(result.current.page).toBe(2);
            expect(result.current.data).toHaveLength(48);

            // Verify EXACTLY ONE call was made for page 2
            const page2Calls = mockGet.mock.calls.filter((c) => (c[0] as string).includes("page=2"));
            expect(page2Calls).toHaveLength(1);
        });

        test("UI test: rapid 20 onEndReached events on FlatList trigger only one page fetch at a time", async () => {
            let resolvePage2!: (val: Record<string, unknown>) => void;
            mockGet.mockImplementation(async (path: string) => {
                if (path.includes("page=2")) {
                    return new Promise((resolve) => {
                        resolvePage2 = resolve;
                    });
                }
                return {
                    bills: [{ id: 1, title: "Bill 1" }],
                    bills_total: 50,
                    all_categories: ["Education"],
                };
            });

            render(<BillsListScreen navigation={makeNav()} />);
            await waitFor(() => expect(screen.getByTestId("bills-list")).toBeTruthy());
            expect(screen.getByText("Bill 1")).toBeTruthy();

            const flatList = screen.getByTestId("bills-list");

            // Fire 20 onEndReached events rapidly
            act(() => {
                for (let i = 0; i < 20; i++) {
                    fireEvent(flatList, "onEndReached");
                }
            });

            // Footer indicator shows loading
            expect(screen.getByTestId("bills-list-loading-more")).toBeTruthy();

            // Resolve page 2
            act(() => {
                resolvePage2({
                    bills: [
                        { id: 1, title: "Bill 1" },
                        { id: 2, title: "Bill 2" },
                    ],
                    bills_total: 50,
                });
            });

            await waitFor(() => expect(screen.getByText("Bill 2")).toBeTruthy());

            const page2Calls = mockGet.mock.calls.filter((c) => (c[0] as string).includes("page=2"));
            expect(page2Calls).toHaveLength(1);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Target 2: Stale response rejection on quick locale switching
    // ─────────────────────────────────────────────────────────────────────────
    describe("Target 2: Stale response rejection on quick locale switching", () => {
        test("delayed responses from earlier locales are discarded and do not overwrite newer locale", async () => {
            const resolvers: Record<number, (val: Record<string, unknown>) => void> = {};

            mockGet.mockImplementation(async (path: string) => {
                const match = path.match(/sway_locale_id=(\d+)/);
                const swayLocaleId = match ? Number(match[1]) : 0;
                return new Promise((resolve) => {
                    resolvers[swayLocaleId] = resolve;
                });
            });

            let currentLocale = 1;
            const { result, rerender } = renderHook<UseBillsResult, { loc: number }>(
                (props: { loc: number }) => useBills(props.loc),
                { initialProps: { loc: currentLocale } },
            );

            // Wait for locale 1 request to hit network
            await waitFor(() => expect(resolvers[1]).toBeDefined());

            // Switch to locale 2 while locale 1 is still pending
            currentLocale = 2;
            rerender({ loc: currentLocale });
            await waitFor(() => expect(resolvers[2]).toBeDefined());

            // Switch to locale 3 while 1 and 2 are pending
            currentLocale = 3;
            rerender({ loc: currentLocale });
            await waitFor(() => expect(resolvers[3]).toBeDefined());

            // Now resolve locale 1 (very stale)
            await act(async () => {
                resolvers[1]({
                    bills: [{ id: 101, title: "Stale Locale 1 Bill" }],
                    bills_total: 1,
                });
            });
            expect(result.current.data).toBeNull(); // Must NOT adopt locale 1

            // Now resolve locale 2 (also stale)
            await act(async () => {
                resolvers[2]({
                    bills: [{ id: 201, title: "Stale Locale 2 Bill" }],
                    bills_total: 1,
                });
            });
            expect(result.current.data).toBeNull(); // Must NOT adopt locale 2

            // Now resolve locale 3 (current)
            await act(async () => {
                resolvers[3]({
                    bills: [{ id: 301, title: "Fresh Locale 3 Bill" }],
                    bills_total: 1,
                });
            });

            expect(result.current.data).toEqual([{ id: 301, title: "Fresh Locale 3 Bill" }]);

            // Cache was only updated for locale 3
            expect(mockCacheSet).toHaveBeenCalledWith(3, [{ id: 301, title: "Fresh Locale 3 Bill" }]);
            expect(mockCacheSet).not.toHaveBeenCalledWith(1, expect.anything());
            expect(mockCacheSet).not.toHaveBeenCalledWith(2, expect.anything());
        });

        test("locale bounce (1 -> 2 -> 1): delayed generation 1 response cannot overwrite generation 3", async () => {
            const genResolvers: ((val: Record<string, unknown>) => void)[] = [];

            mockGet.mockImplementation(async () => {
                return new Promise((resolve) => {
                    genResolvers.push(resolve);
                });
            });

            const { result, rerender } = renderHook<UseBillsResult, { loc: number }>(
                (props: { loc: number }) => useBills(props.loc),
                { initialProps: { loc: 1 } },
            );

            // Wait for gen 1 fetch
            await waitFor(() => expect(genResolvers.length).toBe(1));

            // Switch to locale 2
            rerender({ loc: 2 });
            await waitFor(() => expect(genResolvers.length).toBe(2));

            // Switch back to locale 1
            rerender({ loc: 1 });
            await waitFor(() => expect(genResolvers.length).toBe(3));

            // Resolve gen 1 (old locale 1 response)
            await act(async () => {
                genResolvers[0]({
                    bills: [{ id: 11, title: "Old Gen 1 Bill" }],
                    bills_total: 1,
                });
            });
            expect(result.current.data).toBeNull(); // Old response rejected

            // Resolve gen 3 (current locale 1 response)
            await act(async () => {
                genResolvers[2]({
                    bills: [{ id: 13, title: "Current Gen 3 Bill" }],
                    bills_total: 1,
                });
            });
            expect(result.current.data).toEqual([{ id: 13, title: "Current Gen 3 Bill" }]);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Target 3: Offline transitions
    // ─────────────────────────────────────────────────────────────────────────
    describe("Target 3: Offline cache behavior and offline-to-online transition", () => {
        test("offline serves cached bills instantly and disables further paging requests", async () => {
            mockIsOnlineState = false;
            const cachedBills = Array.from({ length: 24 }, (_, i) => ({
                id: i + 1,
                title: `Cached Bill ${i + 1}`,
            }));
            mockCacheGet.mockResolvedValue(cachedBills.map((b) => ({ bill: b, cachedAt: Date.now() })));

            const { result } = renderHook(() => useBills(42));
            await waitFor(() => expect(result.current.loading).toBe(false));

            expect(result.current.data).toEqual(cachedBills);
            expect(result.current.isOnline).toBe(false);
            expect(result.current.hasMore).toBe(false); // Offline hasMore is false (billsTotal is 0)
            expect(mockGet).not.toHaveBeenCalled();

            // Calling loadMore offline does nothing
            await act(async () => {
                await result.current.loadMore();
            });
            expect(mockGet).not.toHaveBeenCalled();
            expect(result.current.page).toBe(1);
        });

        test("offline-to-online transition triggers automatic refresh and fetches fresh bills", async () => {
            mockIsOnlineState = false;
            const cached = [{ id: 1, title: "Cached Bill" }];
            mockCacheGet.mockResolvedValue([{ bill: cached[0], cachedAt: 1 }]);

            const freshBills = [
                { id: 1, title: "Cached Bill" },
                { id: 2, title: "Fresh Online Bill" },
            ];
            mockGet.mockResolvedValue({
                bills: freshBills,
                bills_total: 2,
            });

            const { result, rerender } = renderHook(() => useBills(42));
            await waitFor(() => expect(result.current.loading).toBe(false));
            expect(result.current.data).toEqual(cached);
            expect(mockGet).not.toHaveBeenCalled();

            // Device transitions to online
            mockIsOnlineState = true;
            rerender({});

            await waitFor(() => expect(result.current.data).toEqual(freshBills));
            expect(mockGet).toHaveBeenCalledWith(expect.stringContaining("page=1"));
            expect(result.current.hasMore).toBe(false);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Target 4: Page error retry
    // ─────────────────────────────────────────────────────────────────────────
    describe("Target 4: Page error retry mechanics", () => {
        test("failed page expansion keeps page counter, displays retry banner, and retries the exact failed page", async () => {
            let page2Attempt = 0;
            mockGet.mockImplementation(async (path: string) => {
                if (path.includes("page=2")) {
                    page2Attempt += 1;
                    if (page2Attempt === 1) {
                        throw new Error("HTTP 503 Service Unavailable");
                    }
                    return {
                        bills: [
                            { id: 1, title: "Bill 1" },
                            { id: 2, title: "Bill 2" },
                        ],
                        bills_total: 2,
                    };
                }
                return {
                    bills: [{ id: 1, title: "Bill 1" }],
                    bills_total: 2,
                    all_categories: ["Housing"],
                };
            });

            render(<BillsListScreen navigation={makeNav()} />);
            await waitFor(() => expect(screen.getByText("Bill 1")).toBeTruthy());

            const flatList = screen.getByTestId("bills-list");

            // Trigger onEndReached to fetch page 2
            fireEvent(flatList, "onEndReached");

            // Wait for error banner
            await waitFor(() => expect(screen.getByTestId("bills-list-page-error")).toBeTruthy());
            expect(screen.getByText("Could not load more bills.")).toBeTruthy();
            const retryButton = screen.getByTestId("bills-retry-load-more");
            expect(retryButton).toBeTruthy();

            // Press retry
            fireEvent.press(retryButton);

            // Wait for success
            await waitFor(() => expect(screen.getByText("Bill 2")).toBeTruthy());
            expect(screen.queryByTestId("bills-list-page-error")).toBeNull();

            // Confirm page 2 was called twice (initial + retry)
            const page2Calls = mockGet.mock.calls.filter((c) => (c[0] as string).includes("page=2"));
            expect(page2Calls).toHaveLength(2);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Target 5: Filter / search empty state and server expansion
    // ─────────────────────────────────────────────────────────────────────────
    describe("Target 5: Filter / search empty state server expansion button", () => {
        test("when search matches 0 bills in window but hasMore=true, server expansion prompt appears and clicking loads page 2", async () => {
            mockGet.mockImplementation(async (path: string) => {
                if (path.includes("page=2")) {
                    return {
                        bills: [
                            { id: 1, title: "Alpha Act" },
                            { id: 2, title: "Zebra Ordinance" },
                        ],
                        bills_total: 2,
                        all_categories: ["Zoning"],
                    };
                }
                return {
                    bills: [{ id: 1, title: "Alpha Act" }],
                    bills_total: 2,
                    all_categories: ["Zoning"],
                };
            });

            render(<BillsListScreen navigation={makeNav()} />);
            await waitFor(() => expect(screen.getByText("Alpha Act")).toBeTruthy());

            // Type search term that doesn't match page 1 ("Zebra")
            fireEvent.changeText(screen.getByTestId("bills-search-input"), "Zebra");

            // FlatList stays mounted, empty state and search expansion prompt are rendered
            expect(screen.getByTestId("bills-list")).toBeTruthy();
            expect(screen.getByTestId("bills-empty-state")).toBeTruthy();
            expect(screen.getByTestId("bills-search-expand-prompt")).toBeTruthy();

            const expandBtn = screen.getByTestId("bills-load-next-page");
            expect(expandBtn).toBeTruthy();

            // Press "Load more from server"
            fireEvent.press(expandBtn);

            // Page 2 arrives with "Zebra Ordinance"
            await waitFor(() => expect(screen.getByText("Zebra Ordinance")).toBeTruthy());

            // Empty state and expansion prompt are gone
            expect(screen.queryByTestId("bills-empty-state")).toBeNull();
            expect(screen.queryByTestId("bills-search-expand-prompt")).toBeNull();
        });

        test("when search matches 0 bills and hasMore=false (entire database loaded), expansion prompt does NOT appear", async () => {
            mockGet.mockResolvedValue({
                bills: [{ id: 1, title: "Alpha Act" }],
                bills_total: 1, // hasMore = false
                all_categories: ["Zoning"],
            });

            render(<BillsListScreen navigation={makeNav()} />);
            await waitFor(() => expect(screen.getByText("Alpha Act")).toBeTruthy());

            fireEvent.changeText(screen.getByTestId("bills-search-input"), "NonExistentBill");

            expect(screen.getByTestId("bills-empty-state")).toBeTruthy();
            expect(screen.queryByTestId("bills-search-expand-prompt")).toBeNull();
        });
    });
});
