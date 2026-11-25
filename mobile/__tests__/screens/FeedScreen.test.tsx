import React from "react";
import { FlatList } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

const mockApiGet = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
    },
}));

const mockShareBill = jest.fn(async () => {});
jest.mock("../../src/hooks/useShareBill", () => ({
    useShareBill: () => ({ shareBill: mockShareBill }),
}));

let mockReachability = { isOnline: true, isResolved: true };
jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => mockReachability,
}));

const mockDispatch = jest.fn();
const mockGetParent = jest.fn(() => ({ navigate: jest.fn() }));
let mockFocusCallbacks: (() => void | (() => void))[] = [];
jest.mock("@react-navigation/native", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        ...jest.requireActual("@react-navigation/native"),
        useNavigation: () => ({ dispatch: mockDispatch, getParent: mockGetParent }),
        DrawerActions: { openDrawer: () => ({ type: "OPEN_DRAWER" }) },
        useFocusEffect: (cb: () => void | (() => void)) => {
            ReactMod.useEffect(() => {
                mockFocusCallbacks.push(cb);
                const cleanup = cb();
                return () => {
                    mockFocusCallbacks = mockFocusCallbacks.filter((fn) => fn !== cb);
                    if (typeof cleanup === "function") cleanup();
                };
            }, [cb]);
        },
    };
});

jest.mock("../../src/components/SkeletonCard", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
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

jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

import FeedScreen from "../../src/screens/FeedScreen";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { IFeedBill, IFeedItem } from "../../src/components/feed/types";

function makeNav() {
    return { navigate: jest.fn() };
}

const TODAY_ISO = new Date().toISOString();
const YESTERDAY_ISO = new Date(Date.now() - 86_400_000).toISOString();

const ALL_KIND_ITEMS: IFeedItem[] = [
    {
        key: "botm-1",
        kind: "bill_of_the_month_released",
        occurred_at: "2026-04-01T00:00:00Z",
        sway_locale: { id: 1, name: "Baltimore" },
        bill: {
            id: 101,
            external_id: "CB-26-0101",
            title: "Clean Harbor Act",
            summary: "Requires stormwater capture on new waterfront developments.",
            view_count: 82,
            share_count: 5,
            summary_ai_unreviewed: false,
        },
        legislator: null,
        legislators: [],
        organization: null,
        user_support: null,
        legislator_support: null,
        agreement: null,
    },
    {
        key: "leg-vote-1",
        kind: "legislator_voted",
        occurred_at: TODAY_ISO,
        sway_locale: { id: 2, name: "Maryland" },
        bill: {
            id: 102,
            external_id: "HB-204",
            title: "Transit Funding Expansion",
            summary: null,
            view_count: 110,
            share_count: 9,
            summary_ai_unreviewed: false,
        },
        legislator: {
            id: 7,
            full_name: "Del. Maya Patel",
            title: "Delegate",
            district_name: "District 46",
            photo_url: null,
        },
        legislators: [],
        organization: null,
        user_support: "FOR",
        legislator_support: "FOR",
        agreement: "agree",
    },
    {
        key: "leg-vote-2",
        kind: "legislator_voted",
        occurred_at: YESTERDAY_ISO,
        sway_locale: { id: 2, name: "Maryland" },
        bill: {
            id: 103,
            external_id: "SB-88",
            title: "Grid Modernization Bill",
            summary: null,
            view_count: 41,
            share_count: 2,
            summary_ai_unreviewed: false,
        },
        legislator: {
            id: 8,
            full_name: "Sen. Carlos Ruiz",
            title: "Senator",
            district_name: "District 46",
            photo_url: null,
        },
        legislators: [],
        organization: null,
        user_support: "FOR",
        legislator_support: "AGAINST",
        agreement: "differ",
    },
    {
        key: "org-pos-1",
        kind: "organization_position_taken",
        occurred_at: YESTERDAY_ISO,
        sway_locale: { id: 2, name: "Maryland" },
        bill: {
            id: 104,
            external_id: "HB-512",
            title: "Tenant Right to Counsel",
            summary: null,
            view_count: 64,
            share_count: 7,
            summary_ai_unreviewed: false,
        },
        legislator: null,
        legislators: [],
        organization: {
            id: 12,
            name: "Maryland Renters United",
            support: "Support",
        },
        user_support: null,
        legislator_support: null,
        agreement: null,
    },
    {
        key: "term-1",
        kind: "legislative_term_began",
        occurred_at: "2026-01-14T00:00:00Z",
        sway_locale: { id: 2, name: "Maryland" },
        bill: null,
        legislator: null,
        legislators: [],
        organization: null,
        user_support: null,
        legislator_support: null,
        agreement: null,
    },
    {
        key: "reps-1",
        kind: "representatives_found",
        occurred_at: "2026-01-05T12:00:00Z",
        sway_locale: null,
        bill: null,
        legislator: null,
        legislators: [
            {
                id: 7,
                full_name: "Del. Maya Patel",
                title: "Delegate",
                district_name: "District 46",
                photo_url: null,
            },
        ],
        organization: null,
        user_support: null,
        legislator_support: null,
        agreement: null,
    },
    {
        key: "joined-1",
        kind: "user_joined",
        occurred_at: "2026-01-05T11:55:00Z",
        sway_locale: null,
        bill: null,
        legislator: null,
        legislators: [],
        organization: null,
        user_support: null,
        legislator_support: null,
        agreement: null,
    },
];

describe("FeedScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockReset();
        mockReachability = { isOnline: true, isResolved: true };
        mockFocusCallbacks = [];
    });

    it("renders all 6 feed item kinds with parity copy, BAL tile, date headings, vote comparison, and counts", async () => {
        mockApiGet.mockResolvedValueOnce({
            items: ALL_KIND_ITEMS,
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        await waitFor(() => expect(screen.getByText("Clean Harbor Act")).toBeTruthy());

        expect(screen.getByText(PARITY_COPY.feed.dateHeadings.today)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.dateHeadings.yesterday)).toBeTruthy();

        expect(screen.getByText("BAL")).toBeTruthy();
        expect(screen.getByText(/Baltimore/)).toBeTruthy();
        expect(screen.getByText(/released the April Bill of the Month/)).toBeTruthy();
        expect(screen.getByText("CB-26-0101")).toBeTruthy();
        expect(screen.getByText("Requires stormwater capture on new waterfront developments.")).toBeTruthy();
        expect(screen.queryByText(/^\d+ voted$/)).toBeNull();
        expect(screen.getByText(PARITY_COPY.feed.viewedCount(82))).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.sharedCount(5))).toBeTruthy();

        expect(screen.getAllByText(/voted on a bill you voted on/).length).toBeGreaterThanOrEqual(1);
        expect(screen.getByText(PARITY_COPY.feed.voteLabels.agree)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.voteLabels.differ)).toBeTruthy();

        expect(screen.getByText(/Maryland Renters United/)).toBeTruthy();
        expect(screen.getByText(/supports a Maryland bill/)).toBeTruthy();

        expect(screen.getByText(PARITY_COPY.feed.legislativeTermBegan("Maryland"))).toBeTruthy();

        expect(screen.getByText(/found your representatives/)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.seeYourRepresentatives)).toBeTruthy();

        expect(screen.getByText(/joined Sway/)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.userJoinedSummary)).toBeTruthy();
    });

    it("strips 'FOR the purpose of' clauses from bill titles and cleans or omits pending/Markdown summaries", async () => {
        mockApiGet.mockResolvedValueOnce({
            items: [
                {
                    ...ALL_KIND_ITEMS[0],
                    key: "botm-clean",
                    bill: {
                        id: 601,
                        external_id: "CB-26-0601",
                        title: "Urban Tree Canopy - Street Planting FOR the purpose of requiring tree planting along arterial streets.",
                        summary:
                            "## OverviewNEWLINERequires **Baltimore** to plant [street trees](https://example.com/trees) on *arterial* corridors.ENDING",
                        view_count: 11,
                        share_count: 1,
                        summary_ai_unreviewed: false,
                    },
                },
                {
                    ...ALL_KIND_ITEMS[0],
                    key: "botm-pending",
                    bill: {
                        id: 602,
                        external_id: "HB-602",
                        title: "Pending Summary Bill",
                        summary: "Summary pending",
                        view_count: 0,
                        share_count: 0,
                        summary_ai_unreviewed: false,
                    },
                },
            ],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findByText("Urban Tree Canopy — Street Planting");
        expect(screen.queryByText(/FOR the purpose of/i)).toBeNull();
        expect(
            screen.getByText("Overview Requires Baltimore to plant street trees on arterial corridors."),
        ).toBeTruthy();
        expect(screen.queryByText(/NEWLINE|ENDING/)).toBeNull();
        expect(screen.queryByText("Summary pending")).toBeNull();
    });

    it("shows the AI unreviewed notice under a Bill of the Month summary only when summary_ai_unreviewed is true", async () => {
        const botmBill = ALL_KIND_ITEMS[0].bill as IFeedBill;
        mockApiGet.mockResolvedValueOnce({
            items: [
                {
                    ...ALL_KIND_ITEMS[0],
                    key: "botm-unreviewed",
                    bill: { ...botmBill, id: 701, summary_ai_unreviewed: true },
                },
                {
                    ...ALL_KIND_ITEMS[0],
                    key: "botm-reviewed",
                    bill: { ...botmBill, id: 702, summary_ai_unreviewed: false },
                },
            ],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findAllByText("Requires stormwater capture on new waterfront developments.");
        expect(screen.getAllByTestId("ai-unreviewed-notice")).toHaveLength(1);
        expect(screen.getByText(PARITY_COPY.bill.aiUnreviewedNotice)).toBeTruthy();
    });

    it("keeps loading skeleton visible on cold launch while reachability is unresolved, then loads once online", async () => {
        mockReachability = { isOnline: false, isResolved: false };
        mockApiGet.mockResolvedValueOnce({
            items: [ALL_KIND_ITEMS[0]],
            feed_cursor: null,
            feed_search: null,
        });

        const nav = makeNav();
        const { rerender } = render(<FeedScreen navigation={nav} />);

        expect(screen.getByTestId("feed-loading")).toBeTruthy();
        expect(screen.queryByTestId("feed-empty")).toBeNull();
        expect(mockApiGet).not.toHaveBeenCalled();

        mockReachability = { isOnline: true, isResolved: true };
        rerender(<FeedScreen navigation={nav} />);

        await screen.findByText("Clean Harbor Act");
        expect(mockApiGet).toHaveBeenCalledTimes(1);
    });

    it("renders offline retry state instead of empty state when reachability resolves offline", async () => {
        mockReachability = { isOnline: false, isResolved: true };

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findByTestId("feed-offline");
        expect(screen.queryByText(PARITY_COPY.feed.emptyState)).toBeNull();
        expect(screen.getByText("Reconnect to load your feed.")).toBeTruthy();
    });

    it("renders feed-error instead of stale unfiltered items with a false match count when search fails", async () => {
        jest.useFakeTimers();
        try {
            mockApiGet
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[0]],
                    feed_cursor: null,
                    feed_search: null,
                })
                .mockRejectedValueOnce(new Error("Search request failed"));

            render(<FeedScreen navigation={makeNav()} />);
            await screen.findByText("Clean Harbor Act");

            fireEvent.changeText(screen.getByTestId("feed-search-input"), "Transit");
            await act(async () => {
                jest.advanceTimersByTime(300);
            });

            await screen.findByTestId("feed-error");
            expect(screen.queryByText("Clean Harbor Act")).toBeNull();
            expect(screen.queryByText(PARITY_COPY.feed.searchMatchCount(1, "Transit"))).toBeNull();
        } finally {
            jest.useRealTimers();
        }
    });

    it("refreshes the feed when FeedScreen regains focus after navigating back", async () => {
        mockApiGet
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0]],
                feed_cursor: null,
                feed_search: null,
            })
            .mockResolvedValueOnce({
                items: [{ ...ALL_KIND_ITEMS[0], user_support: "FOR" }],
                feed_cursor: null,
                feed_search: null,
            });

        render(<FeedScreen navigation={makeNav()} />);
        await screen.findByText(PARITY_COPY.feed.voteLabels.goVote);
        expect(mockApiGet).toHaveBeenCalledTimes(1);

        await act(async () => {
            for (const cb of mockFocusCallbacks) {
                cb();
            }
        });

        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
        await screen.findByText(/You voted/);
    });

    it("navigates to BillDetail when pressing Go vote", async () => {
        const nav = makeNav();
        mockApiGet.mockResolvedValueOnce({
            items: [ALL_KIND_ITEMS[0]],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={nav} />);

        const goVoteBtn = await screen.findByText(PARITY_COPY.feed.voteLabels.goVote);
        fireEvent.press(goVoteBtn);

        expect(nav.navigate).toHaveBeenCalledWith("BillDetail", { id: 101 });
    });

    it("triggers native share when pressing Share bill", async () => {
        mockApiGet.mockResolvedValueOnce({
            items: [ALL_KIND_ITEMS[0]],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        const shareBtn = await screen.findByText(PARITY_COPY.bill.shareBill);
        fireEvent.press(shareBtn);

        expect(mockShareBill).toHaveBeenCalledWith({ id: 101, title: "Clean Harbor Act" });
    });

    it("loads the next page with feed_cursor on FlatList onEndReached", async () => {
        mockApiGet
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0]],
                feed_cursor: "cursor-abc",
                feed_search: null,
            })
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[6]],
                feed_cursor: null,
                feed_search: null,
            });

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findByText("Clean Harbor Act");
        expect(mockApiGet).toHaveBeenCalledWith("/feed");

        const list = screen.UNSAFE_getByType(FlatList);
        await act(async () => {
            list.props.onEndReached();
        });

        await waitFor(() => expect(mockApiGet).toHaveBeenCalledWith("/feed?feed_cursor=cursor-abc"));
        await screen.findByText(PARITY_COPY.feed.userJoinedSummary);
    });

    it("reloads from the top on pull to refresh", async () => {
        mockApiGet
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0]],
                feed_cursor: "cursor-abc",
                feed_search: null,
            })
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[6]],
                feed_cursor: null,
                feed_search: null,
            });

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findByText("Clean Harbor Act");

        const list = screen.UNSAFE_getByType(FlatList);
        await act(async () => {
            list.props.refreshControl.props.onRefresh();
        });

        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
        expect(mockApiGet).toHaveBeenLastCalledWith("/feed");
        await screen.findByText(PARITY_COPY.feed.userJoinedSummary);
    });

    it("shows an inline top error banner with Retry when pull-to-refresh fails while preserving existing items", async () => {
        mockApiGet
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0]],
                feed_cursor: null,
                feed_search: null,
            })
            .mockRejectedValueOnce(new Error("Refresh failed"))
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0], ALL_KIND_ITEMS[6]],
                feed_cursor: null,
                feed_search: null,
            });

        render(<FeedScreen navigation={makeNav()} />);
        await screen.findByText("Clean Harbor Act");

        const list = screen.UNSAFE_getByType(FlatList);
        await act(async () => {
            await list.props.refreshControl.props.onRefresh();
        });

        expect(screen.getByTestId("feed-refresh-error")).toBeTruthy();
        expect(screen.getByText("Refresh failed")).toBeTruthy();
        expect(screen.getByText("Clean Harbor Act")).toBeTruthy();
        expect(screen.queryByTestId("feed-error")).toBeNull();

        fireEvent.press(screen.getByLabelText(PARITY_COPY.feed.retry));

        await screen.findByText(PARITY_COPY.feed.userJoinedSummary);
        expect(screen.queryByTestId("feed-refresh-error")).toBeNull();
    });

    it("does not clear a newer generation's loadMore lock when a stale loadMore settles", async () => {
        let resolveStaleLoadMore!: (value: unknown) => void;
        let resolveActiveLoadMore!: (value: unknown) => void;

        mockApiGet
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0]],
                feed_cursor: "cursor-gen-1",
                feed_search: null,
            })
            .mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolveStaleLoadMore = resolve;
                    }),
            )
            .mockResolvedValueOnce({
                items: [ALL_KIND_ITEMS[0]],
                feed_cursor: "cursor-gen-2",
                feed_search: null,
            })
            .mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolveActiveLoadMore = resolve;
                    }),
            );

        render(<FeedScreen navigation={makeNav()} />);
        await screen.findByText("Clean Harbor Act");

        const list = screen.UNSAFE_getByType(FlatList);
        act(() => {
            list.props.onEndReached();
        });
        expect(mockApiGet).toHaveBeenCalledWith("/feed?feed_cursor=cursor-gen-1");

        await act(async () => {
            await list.props.refreshControl.props.onRefresh();
        });
        expect(mockApiGet).toHaveBeenCalledWith("/feed");

        const refreshedList = screen.UNSAFE_getByType(FlatList);
        act(() => {
            refreshedList.props.onEndReached();
        });
        expect(mockApiGet).toHaveBeenCalledWith("/feed?feed_cursor=cursor-gen-2");
        expect(mockApiGet).toHaveBeenCalledTimes(4);

        await act(async () => {
            resolveStaleLoadMore({
                items: [ALL_KIND_ITEMS[5]],
                feed_cursor: null,
                feed_search: null,
            });
        });

        act(() => {
            screen.UNSAFE_getByType(FlatList).props.onEndReached();
        });
        expect(mockApiGet).toHaveBeenCalledTimes(4);

        await act(async () => {
            resolveActiveLoadMore({
                items: [ALL_KIND_ITEMS[6]],
                feed_cursor: null,
                feed_search: null,
            });
        });
        await screen.findByText(PARITY_COPY.feed.userJoinedSummary);
    });

    it("renders empty state when feed returns no items", async () => {
        mockApiGet.mockResolvedValueOnce({
            items: [],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findByText(PARITY_COPY.feed.emptyState);
    });

    it("renders error state and retries on press", async () => {
        mockApiGet.mockRejectedValueOnce(new Error("Feed unavailable")).mockResolvedValueOnce({
            items: [ALL_KIND_ITEMS[6]],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        await screen.findByTestId("feed-error");
        fireEvent.press(screen.getByText("Retry"));

        await screen.findByText(PARITY_COPY.feed.userJoinedSummary);
    });

    it("debounces search input into feed_search, drops prior cursor, and shows match count", async () => {
        jest.useFakeTimers();
        try {
            mockApiGet
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[0]],
                    feed_cursor: "cursor-initial",
                    feed_search: null,
                })
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[1]],
                    feed_cursor: "cursor-search-2",
                    feed_search: "Transit",
                    feed_match_count: 45,
                })
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[6]],
                    feed_cursor: null,
                    feed_search: "Transit",
                    feed_match_count: 45,
                });

            render(<FeedScreen navigation={makeNav()} />);
            await screen.findByText("Clean Harbor Act");

            const input = screen.getByTestId("feed-search-input");
            fireEvent.changeText(input, "Transit");

            expect(mockApiGet).toHaveBeenCalledTimes(1);

            await act(async () => {
                jest.advanceTimersByTime(300);
            });

            await waitFor(() => expect(mockApiGet).toHaveBeenCalledWith("/feed?feed_search=Transit"));
            await screen.findByText(PARITY_COPY.feed.searchMatchCount(45, "Transit"));

            const list = screen.UNSAFE_getByType(FlatList);
            await act(async () => {
                list.props.onEndReached();
            });

            await waitFor(() =>
                expect(mockApiGet).toHaveBeenCalledWith("/feed?feed_search=Transit&feed_cursor=cursor-search-2"),
            );
            await act(async () => {});
            expect(screen.getByText(PARITY_COPY.feed.searchMatchCount(45, "Transit"))).toBeTruthy();
        } finally {
            jest.useRealTimers();
        }
    });

    it("clears search and restores the full feed", async () => {
        jest.useFakeTimers();
        try {
            mockApiGet
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[0]],
                    feed_cursor: null,
                    feed_search: null,
                })
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[1]],
                    feed_cursor: null,
                    feed_search: "Transit",
                })
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[0]],
                    feed_cursor: null,
                    feed_search: null,
                });

            render(<FeedScreen navigation={makeNav()} />);
            await screen.findByText("Clean Harbor Act");

            fireEvent.changeText(screen.getByTestId("feed-search-input"), "Transit");
            await act(async () => {
                jest.advanceTimersByTime(300);
            });
            await screen.findByText("Transit Funding Expansion");

            fireEvent.press(screen.getByTestId("feed-search-clear"));

            await waitFor(() => expect(mockApiGet).toHaveBeenLastCalledWith("/feed"));
            await screen.findByText("Clean Harbor Act");
        } finally {
            jest.useRealTimers();
        }
    });

    it("renders no-match copy with 44pt all bills link when search returns no items", async () => {
        jest.useFakeTimers();
        try {
            const parentNavigate = jest.fn();
            mockGetParent.mockReturnValue({ navigate: parentNavigate });
            mockApiGet
                .mockResolvedValueOnce({
                    items: [ALL_KIND_ITEMS[0]],
                    feed_cursor: null,
                    feed_search: null,
                })
                .mockResolvedValueOnce({
                    items: [],
                    feed_cursor: null,
                    feed_search: "Nonexistent",
                });

            render(<FeedScreen navigation={makeNav()} />);
            await screen.findByText("Clean Harbor Act");

            fireEvent.changeText(screen.getByTestId("feed-search-input"), "Nonexistent");
            await act(async () => {
                jest.advanceTimersByTime(300);
            });

            await screen.findByText(PARITY_COPY.feed.searchNoMatches("Nonexistent"));
            const allBillsLink = screen.getByLabelText(PARITY_COPY.feed.searchBrowseLink);
            expect(allBillsLink).toBeTruthy();
            fireEvent.press(screen.getByText(PARITY_COPY.feed.searchBrowseLink));
            expect(parentNavigate).toHaveBeenCalledWith("Bills", { screen: "BillsList", pop: true });
        } finally {
            jest.useRealTimers();
        }
    });

    it("navigates to LegislatorsList on parent drawer when pressing See your representatives", async () => {
        const parentNavigate = jest.fn();
        mockGetParent.mockReturnValue({ navigate: parentNavigate });
        mockApiGet.mockResolvedValueOnce({
            items: [ALL_KIND_ITEMS[5]],
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);
        const repsBtn = await screen.findByText(PARITY_COPY.feed.seeYourRepresentatives);
        fireEvent.press(repsBtn);

        expect(parentNavigate).toHaveBeenCalledWith("Legislators", { screen: "LegislatorsList", pop: true });
    });
});
