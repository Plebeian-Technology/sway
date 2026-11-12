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

let mockIsOnline = true;
jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: mockIsOnline, isResolved: true }),
}));

const mockDispatch = jest.fn();
const mockGetParent = jest.fn(() => ({ navigate: jest.fn() }));
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ dispatch: mockDispatch, getParent: mockGetParent }),
    DrawerActions: { openDrawer: () => ({ type: "OPEN_DRAWER" }) },
}));

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
import type { IFeedItem } from "../../src/components/feed/types";

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
        sway_locale: { id: 1, name: "Baltimore City" },
        bill: {
            id: 101,
            external_id: "CB-26-0101",
            title: "Clean Harbor Act",
            summary: "Requires stormwater capture on new waterfront developments.",
            vote_count: 14,
            view_count: 82,
            share_count: 5,
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
            vote_count: 23,
            view_count: 110,
            share_count: 9,
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
            vote_count: 8,
            view_count: 41,
            share_count: 2,
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
            vote_count: 19,
            view_count: 64,
            share_count: 7,
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
        mockIsOnline = true;
    });

    it("renders all 6 feed item kinds with parity copy, date headings, vote comparison, and counts", async () => {
        mockApiGet.mockResolvedValueOnce({
            items: ALL_KIND_ITEMS,
            feed_cursor: null,
            feed_search: null,
        });

        render(<FeedScreen navigation={makeNav()} />);

        await waitFor(() => expect(screen.getByText("Clean Harbor Act")).toBeTruthy());

        // Date headings
        expect(screen.getByText(PARITY_COPY.feed.dateHeadings.today)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.dateHeadings.yesterday)).toBeTruthy();

        // bill_of_the_month_released
        expect(screen.getByText(/Baltimore City/)).toBeTruthy();
        expect(screen.getByText(/released the April Bill of the Month/)).toBeTruthy();
        expect(screen.getByText("CB-26-0101")).toBeTruthy();
        expect(screen.getByText("Requires stormwater capture on new waterfront developments.")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.votedCount(14))).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.viewedCount(82))).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.sharedCount(5))).toBeTruthy();

        // legislator_voted (agree & differ)
        expect(screen.getAllByText(/voted on a bill you voted on/).length).toBeGreaterThanOrEqual(1);
        expect(screen.getByText(PARITY_COPY.feed.voteLabels.agree)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.voteLabels.differ)).toBeTruthy();

        // organization_position_taken
        expect(screen.getByText(/Maryland Renters United/)).toBeTruthy();
        expect(screen.getByText(/supports a Maryland bill/)).toBeTruthy();

        // legislative_term_began
        expect(screen.getByText(PARITY_COPY.feed.legislativeTermBegan("Maryland"))).toBeTruthy();

        // representatives_found
        expect(screen.getByText(/found your representatives/)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.seeYourRepresentatives)).toBeTruthy();

        // user_joined
        expect(screen.getByText(/joined Sway/)).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.feed.userJoinedSummary)).toBeTruthy();
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
});
