const mockUseBill = jest.fn();
const mockUseFocusedSync = jest.fn();
const mockUseBootstrap = jest.fn();
const mockUseSession = jest.fn();

jest.mock("../../src/hooks/useBill", () => ({
    useBill: () => mockUseBill(),
}));
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: (opts: unknown) => mockUseFocusedSync(opts),
}));
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

// VotePanel reaches for useSession and useCastUserVote. Stand in for both so the
// component renders without dragging in the whole sign-in system.
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => mockUseSession(),
}));
jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => ({ submit: jest.fn(async () => ({})), isOnline: true }),
}));
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));
jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));
jest.mock("react-native-reanimated", () => require("react-native-reanimated/mock"));

// SkeletonCard uses react-native-reanimated, which under jest-expo pulls in
// native animation code. Replace it so rendering this screen never reaches
// that far.
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

import React from "react";
import { act, fireEvent, render, screen } from "@testing-library/react-native";
import BillDetailScreen from "../../src/screens/BillDetailScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { swayTokens } from "../../src/theme/tokens";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const route = { params: { id: 42 } };

interface JsonNode {
    props?: { testID?: string };
    children?: unknown[] | null;
}

// @lat: [[bill-detail-error-recovery#Why the error snapshot stops at the empty state]]
const findByTestId = (node: unknown, testID: string): JsonNode | null => {
    const candidate = node as JsonNode | null;
    if (!candidate || typeof candidate !== "object") return null;
    if (candidate.props?.testID === testID) return candidate;
    for (const child of candidate.children ?? []) {
        const found = findByTestId(child, testID);
        if (found) return found;
    }
    return null;
};

// Card and SwayLocalePickerSheet call useTheme, so wrap every render in ThemeProvider.
const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const testIDsInOrder = () =>
    screen.UNSAFE_root.findAll((node: { props: Record<string, unknown> }) => typeof node.props.testID === "string").map(
        (node: { props: Record<string, unknown> }) => node.props.testID as string,
    );

const expectInOrder = (order: string[]) => {
    const allTestIDs = testIDsInOrder();
    const positions = order.map((id) => allTestIDs.indexOf(id));
    for (let i = 0; i < order.length; i++) {
        expect(positions[i]).toBeGreaterThan(-1);
    }
    for (let i = 1; i < positions.length; i++) {
        expect(positions[i]).toBeGreaterThan(positions[i - 1]);
    }
};

const fullBillPayload = {
    bill: {
        id: 42,
        title: "Open Records Act",
        bill_number: "HB 1234",
        external_id: "HB1234",
        status: "Passed",
        status_color: "#5fcf89",
        summary:
            "A detailed Sway summary of the bill for testing purposes that goes beyond 200 characters to test the show more feature. This is extra text to push past the preview threshold used by BillSummarySection component.",
        link: "https://mgaleg.maryland.gov/bills/HB1234",
        legislator_id: 7,
        sway_locale_id: 1,
    },
    sponsor: { full_name: "Alice Q. Sponsor" },
    user_vote: { support: "for" },
    bill_score: {
        id: 7,
        bill_id: 42,
        for: 100,
        against: 50,
        comparison_suppressed: false,
        voters_needed: 0,
        districts: [
            {
                bill_score_id: 7,
                district: { name: "MD1", number: 1, region_code: "MD" },
                comparison_suppressed: false,
                for_percent: 60,
                against_percent: 40,
                at_large: false,
            },
            {
                bill_score_id: 7,
                district: { name: "MD2", number: 2, region_code: "MD" },
                comparison_suppressed: false,
                for_percent: 43,
                against_percent: 57,
                at_large: false,
            },
        ],
    },
    districts: [{ name: "MD1", number: 1, region_code: "MD" }],
    organizations: [
        {
            id: 1,
            support: "FOR",
            organization: { name: "Supporters Org" },
            summary: "We support this because it improves access.",
        },
        {
            id: 2,
            support: "AGAINST",
            organization: { name: "Opponents Org" },
            summary: "We oppose this for budgetary reasons.",
        },
    ],
    public_testimony_counts: null,
};

const COUNTS = { total: 6, support: 3, oppose: 2, neutral: 1 };

const signedIn = () =>
    mockUseSession.mockReturnValue({
        isAuthenticated: true,
        loading: false,
        signOut: jest.fn(),
        signOutAll: jest.fn(),
    });

const withParentNavigate = (run: (parentNavigate: jest.Mock) => void) => {
    const parentNavigate = jest.fn();
    const navigation = jest.requireMock<typeof import("@react-navigation/native")>("@react-navigation/native");
    const spy = jest
        .spyOn(navigation, "useNavigation")
        .mockReturnValue({ getParent: () => ({ navigate: parentNavigate }) } as never);
    try {
        run(parentNavigate);
    } finally {
        spy.mockRestore();
    }
};

describe("BillDetailScreen", () => {
    test("compare-with-reps lands on the legislators list even from inside the Legislators tab", () => {
        const parentNavigate = jest.fn();
        const navigation = jest.requireMock<typeof import("@react-navigation/native")>("@react-navigation/native");
        const spy = jest
            .spyOn(navigation, "useNavigation")
            .mockReturnValue({ getParent: () => ({ navigate: parentNavigate }) } as never);
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-votes"));
        fireEvent.press(screen.getByLabelText("Compare your vote with your representatives"));
        expect(parentNavigate).toHaveBeenCalledWith("Legislators", { screen: "LegislatorsList", pop: true });
        spy.mockRestore();
    });

    beforeEach(() => {
        mockUseBill.mockReset();
        mockUseFocusedSync.mockReset();
        mockUseSession.mockReturnValue({
            isAuthenticated: false,
            loading: false,
            signOut: jest.fn(),
            signOutAll: jest.fn(),
        });
        mockUseBootstrap.mockReturnValue({
            bootstrap: { locale: { id: 1, name: "baltimore-maryland-united_states" } },
            loading: false,
        });
    });

    test("renders skeleton while loading and no data", () => {
        mockUseBill.mockReturnValue({ data: null, loading: true, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        expect(screen.getByTestId("bill-detail-skeleton")).toBeTruthy();
    });

    test("renders EmptyState error when fetch fails with PARITY_COPY.billDetailError", () => {
        mockUseBill.mockReturnValue({ data: null, loading: false, error: new Error("boom"), refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        expect(screen.getByTestId("bill-detail-error")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.bill.detailError)).toBeTruthy();
    });

    // @lat: [[bill-detail-error-recovery#Reaching a retry when the bill will not load]]
    test("error state offers a Try again control that refetches the bill", () => {
        const refresh = jest.fn();
        mockUseBill.mockReturnValue({ data: null, loading: false, error: new Error("boom"), refresh });
        wrap(<BillDetailScreen route={route} />);

        const retry = screen.getByTestId("bill-detail-empty-cta");
        expect(screen.getByText(PARITY_COPY.legislators.historyRetry)).toBeTruthy();

        fireEvent.press(retry);
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("error state carries a pull-to-refresh bound to the same refetch", () => {
        const refresh = jest.fn();
        mockUseBill.mockReturnValue({ data: null, loading: false, error: new Error("boom"), refresh });
        wrap(<BillDetailScreen route={route} />);

        const scroll = screen.getByTestId("bill-detail-error");
        act(() => {
            scroll.props.refreshControl.props.onRefresh();
        });
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("opens on the Bill tab: the hero card and summary show and the Votes and Summaries sections do not", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        expect(screen.getByTestId("bill-detail-hero")).toBeTruthy();
        expect(screen.getByText("Open Records Act")).toBeTruthy();
        expect(screen.getByTestId("vote-panel")).toBeTruthy();
        expect(screen.getByTestId("bill-summary-section")).toBeTruthy();
        expect(screen.queryByTestId("bill-score-bar")).toBeNull();
        expect(screen.queryByTestId("take-next-step")).toBeNull();
        expect(screen.queryByTestId("org-positions-section")).toBeNull();
    });

    test("the Bill tab carries information about the bill, not only the vote buttons", () => {
        const richPayload = {
            ...fullBillPayload,
            bill: {
                id: 42,
                title: "Open Records Act FOR the purpose of requiring agencies to publish their records online",
                external_id: "HB1234",
                chamber: "House",
                status: "passed",
                summary: "A detailed Sway summary of the bill.",
                link: "https://mgaleg.maryland.gov/bills/HB1234",
                categories: ["Transparency"],
                active: true,
                vote_date_time_utc: "2026-03-03T17:00:00Z",
                house_vote_date_time_utc: "2026-03-03T17:00:00Z",
                senate_vote_date_time_utc: null,
            },
        };
        mockUseBill.mockReturnValue({ data: richPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);

        expect(screen.getByText("Open Records Act")).toBeTruthy();
        expect(screen.getByText(/Sponsored by Alice Q\. Sponsor/)).toBeTruthy();
        expect(screen.getByText("Transparency")).toBeTruthy();
        expect(screen.getByTestId("bill-header-status")).toBeTruthy();
        expect(screen.getByText("House voted on March 3, 2026.")).toBeTruthy();
        expect(screen.getByTestId("bill-summary-section")).toBeTruthy();
        expect(screen.getByText("A detailed Sway summary of the bill.")).toBeTruthy();
        expect(screen.getByTestId("bill-as-introduced")).toBeTruthy();
        expect(screen.getByText(/FOR the purpose of requiring agencies to publish their records online/)).toBeTruthy();
    });

    test("a bill no one has voted on yet says so", () => {
        const unvoted = {
            ...fullBillPayload,
            bill: { ...fullBillPayload.bill, vote_date_time_utc: null, house_vote_date_time_utc: null },
        };
        mockUseBill.mockReturnValue({ data: unvoted, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);

        expect(screen.getByText(PARITY_COPY.bill.voteStatus.notYetVoted)).toBeTruthy();
    });

    test("the Votes tab shows VotePanel, BillScoreBar, DistrictVotesPanel and HearingTestimonySection", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.getByTestId("vote-panel-for")).toBeTruthy();
        expect(screen.getByTestId("bill-score-bar")).toBeTruthy();
        expect(screen.getByTestId("district-votes-panel")).toBeTruthy();
        expect(screen.getByTestId("take-next-step")).toBeTruthy();
        expect(screen.queryByTestId("bill-detail-hero")).toBeNull();
        expect(screen.queryByTestId("bill-summary-section")).toBeNull();
    });

    test("the Summaries tab shows OrgPositionsSection, and the summary stays on the Bill tab", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByTestId("bill-summary-section")).toBeNull();
        expect(screen.queryByTestId("bill-detail-hero")).toBeNull();
        expect(screen.queryByTestId("take-next-step")).toBeNull();
    });

    // @lat: [[user-vote-submission#Mobile screen coverage]]
    test("D-13 sections keep their order inside each tab: Bill, then Votes, then Summaries", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        expectInOrder(["broadside-tab-strip", "bill-header", "vote-panel", "bill-summary-section"]);
        fireEvent.press(screen.getByTestId("tab-votes"));
        expectInOrder(["vote-panel", "bill-score-bar", "district-votes-panel", "take-next-step"]);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expectInOrder(["bill-detail-summaries", "org-positions-section"]);
    });

    test("calls useFocusedSync with the refresh callback and a 15000ms poll", () => {
        mockUseBill.mockReturnValue({
            data: { bill: { id: 1, title: "T" } },
            loading: false,
            error: null,
            refresh: jest.fn(),
        });
        wrap(<BillDetailScreen route={route} />);
        expect(mockUseFocusedSync).toHaveBeenCalled();
        const arg = mockUseFocusedSync.mock.calls[0][0] as { refresh: unknown; pollMs: number };
        expect(typeof arg.refresh).toBe("function");
        expect(arg.pollMs).toBe(15000);
    });

    test("hands useFocusedSync the same refresh function on every render, so the poll and cable subscription are not rebuilt", () => {
        const refresh = jest.fn();
        mockUseBill.mockImplementation(() => ({ data: fullBillPayload, loading: false, error: null, refresh }));
        const { rerender } = wrap(<BillDetailScreen route={route} />);
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={route} />
            </ThemeProvider>,
        );

        const refreshes = mockUseFocusedSync.mock.calls.map((call: [{ refresh: () => void }]) => call[0].refresh);
        expect(refreshes.length).toBeGreaterThanOrEqual(2);
        expect(new Set(refreshes).size).toBe(1);
    });

    test("the Votes tab draws the reader's district from the detail response and compares it with their vote", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-votes"));

        expect(screen.getByTestId("district-votes-reader")).toBeTruthy();
        expect(screen.getByTestId("district-votes-alignment")).toHaveTextContent(
            "Your vote matches your district's majority.",
        );
    });

    describe("a bill from a locale other than the one the reader is browsing", () => {
        const rowBackground = (id: string) =>
            Object.assign({}, ...[screen.getByTestId(id).props.style].flat(Infinity).filter(Boolean)).backgroundColor;

        test("shows the tally but marks no district as the reader's, even when a district number collides", () => {
            const otherLocaleBill = { ...fullBillPayload, bill: { ...fullBillPayload.bill, sway_locale_id: 2 } };
            mockUseBill.mockReturnValue({ data: otherLocaleBill, loading: false, error: null, refresh: jest.fn() });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-votes"));

            expect(screen.getByTestId("district-votes-panel")).toBeTruthy();
            expect(screen.queryByTestId("district-votes-reader")).toBeNull();
            expect(screen.queryByTestId("district-votes-alignment")).toBeNull();
            expect(rowBackground("district-votes-row-1")).toBeUndefined();
        });

        test("marks no district when the bill does not say which locale it belongs to", () => {
            const { sway_locale_id: _omitted, ...billWithoutLocale } = fullBillPayload.bill;
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, bill: billWithoutLocale },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-votes"));

            expect(screen.queryByTestId("district-votes-reader")).toBeNull();
        });

        test("marks no district when the active locale is unknown", () => {
            mockUseBootstrap.mockReturnValue({ bootstrap: null, loading: false });
            mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-votes"));

            expect(screen.queryByTestId("district-votes-reader")).toBeNull();
        });

        test("marks the reader's district again for a bill from the active locale", () => {
            mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-votes"));

            expect(screen.getByTestId("district-votes-reader")).toBeTruthy();
            expect(rowBackground("district-votes-row-1")).toBe(swayTokens.light.surface3);
        });
    });

    test("the Votes tab shows the tally but no reader district when the response carries only the at-large district", () => {
        const signedOut = {
            ...fullBillPayload,
            districts: [{ name: "MD0", number: 0, region_code: "MD" }],
        };
        mockUseBill.mockReturnValue({ data: signedOut, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-votes"));

        expect(screen.getByTestId("district-votes-panel")).toBeTruthy();
        expect(screen.queryByTestId("district-votes-reader")).toBeNull();
    });

    test("a bill with no score yet says there are not enough votes instead of showing zeros", () => {
        mockUseBill.mockReturnValue({
            data: { ...fullBillPayload, bill_score: null },
            loading: false,
            error: null,
            refresh: jest.fn(),
        });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-votes"));

        expect(screen.getByText(PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes)).toBeTruthy();
        expect(screen.queryByText(/For: 0/)).toBeNull();
        expect(screen.queryByTestId("district-votes-panel")).toBeNull();
    });

    // @lat: [[user-vote-submission#Mobile screen coverage]]
    test("a vote cast from the Votes tab refreshes the bill once after 1500ms", async () => {
        jest.useFakeTimers();
        const refresh = jest.fn();
        mockUseSession.mockReturnValue({
            isAuthenticated: true,
            loading: false,
            signOut: jest.fn(),
            signOutAll: jest.fn(),
        });
        mockUseBill.mockReturnValue({
            data: { ...fullBillPayload, user_vote: null },
            loading: false,
            error: null,
            refresh,
        });
        wrap(<BillDetailScreen route={route} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        await act(async () => {
            fireEvent.press(screen.getByTestId("vote-panel-for"));
        });
        await act(async () => {
            fireEvent.press(screen.getByTestId("vote-panel-confirm-submit"));
        });
        act(() => {
            jest.advanceTimersByTime(1500);
        });

        expect(refresh).toHaveBeenCalledTimes(1);
        jest.useRealTimers();
    });

    test("the selected tab survives a refetch of the same bill", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        const { rerender } = wrap(<BillDetailScreen route={route} />);

        fireEvent.press(screen.getByTestId("tab-votes"));

        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: true, error: null, refresh: jest.fn() });
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={route} />
            </ThemeProvider>,
        );

        expect(screen.getByTestId("tab-votes").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true }),
        );
        expect(screen.getByTestId("take-next-step")).toBeTruthy();
    });

    test("a bill refetch the reader did not pull for leaves the refresh spinner hidden", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        const { rerender } = wrap(<BillDetailScreen route={route} />);

        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: true, error: null, refresh: jest.fn() });
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={route} />
            </ThemeProvider>,
        );

        expect(screen.getByTestId("bill-detail-scroll").props.refreshControl.props.refreshing).toBe(false);
    });

    test("a pull to refresh shows the refresh spinner until bill loading ends", () => {
        const refresh = jest.fn();
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh });
        const { rerender } = wrap(<BillDetailScreen route={route} />);
        const refreshing = () => screen.getByTestId("bill-detail-scroll").props.refreshControl.props.refreshing;

        act(() => {
            screen.getByTestId("bill-detail-scroll").props.refreshControl.props.onRefresh();
        });
        expect(refresh).toHaveBeenCalledTimes(1);
        expect(refreshing()).toBe(true);

        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: true, error: null, refresh });
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={route} />
            </ThemeProvider>,
        );
        expect(refreshing()).toBe(true);

        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh });
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={route} />
            </ThemeProvider>,
        );
        expect(refreshing()).toBe(false);
    });

    test("VotePanel renders 'Your vote' header from PARITY_COPY.votePanelTitle", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        expect(screen.getByText(PARITY_COPY.votePanel.title)).toBeTruthy();
    });

    test("VotePanel renders For + Against labels from PARITY_COPY", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        expect(screen.getByTestId("vote-panel-for")).toBeTruthy();
        expect(screen.getByTestId("vote-panel-against")).toBeTruthy();
    });

    // toMatchSnapshot() runs out of stack on deep React Native trees — the same
    // problem BillsListScreen ran into. Looking for each testID gives the same
    // assurance without the snapshot.
    test("full render: all D-13 sections present across the three tabs (structural snapshot evidence)", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        const expectedTestIDsByTab = {
            "tab-bill": ["bill-detail-scroll", "bill-header", "vote-panel", "bill-summary-section"],
            "tab-votes": ["vote-panel", "bill-score-bar", "district-votes-panel", "take-next-step"],
            "tab-summaries": ["org-positions-section"],
        };
        Object.entries(expectedTestIDsByTab).forEach(([tab, ids]) => {
            fireEvent.press(screen.getByTestId(tab));
            ids.forEach((id) => expect(screen.getByTestId(id)).toBeTruthy());
        });
    });

    test("renders RelatedNewsArticles section when bill has approved related_articles", () => {
        const payloadWithNews = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                related_articles: [
                    {
                        id: 10,
                        title: "Transit Overhaul Advances",
                        outlet_name: "The Baltimore Sun",
                        author_name: "Emily Vance",
                        published_at: "2026-04-12T14:30:00Z",
                        article_kind: "reporting",
                        match_kind: "direct",
                        url: "https://example.com/story",
                    },
                ],
            },
        };
        mockUseBill.mockReturnValue({ data: payloadWithNews, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("related-news-articles")).toBeTruthy();
        expect(screen.getByText("Transit Overhaul Advances")).toBeTruthy();
        expect(screen.getByText("The Baltimore Sun")).toBeTruthy();
    });

    test("omits RelatedNewsArticles section when bill has empty or null related_articles", () => {
        mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByTestId("related-news-articles")).toBeNull();
    });

    test("preserves vertical order on the Summaries tab: related-news-articles -> org-positions-section", () => {
        const payloadWithNews = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                related_articles: [
                    {
                        id: 10,
                        title: "Transit Overhaul Advances",
                        outlet_name: "The Baltimore Sun",
                        author_name: "Emily Vance",
                        published_at: "2026-04-12T14:30:00Z",
                        article_kind: "reporting",
                        match_kind: "direct",
                        url: "https://example.com/story",
                    },
                ],
            },
        };
        mockUseBill.mockReturnValue({ data: payloadWithNews, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expectInOrder(["related-news-articles", "org-positions-section"]);
    });

    test("switching bill clears previous bill's related articles", () => {
        const payloadWithNews = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                id: 42,
                related_articles: [
                    {
                        id: 10,
                        title: "Bill 42 Exclusive Article",
                        outlet_name: "The Baltimore Sun",
                        author_name: null,
                        published_at: null,
                        article_kind: "reporting",
                        match_kind: "direct",
                        url: "https://example.com/story42",
                    },
                ],
            },
        };
        const payloadWithoutNews = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                id: 43,
                title: "Next Bill Without News",
                related_articles: [],
            },
        };

        mockUseBill.mockReturnValue({ data: payloadWithNews, loading: false, error: null, refresh: jest.fn() });
        const { rerender } = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByText("Bill 42 Exclusive Article")).toBeTruthy();

        mockUseBill.mockReturnValue({ data: payloadWithoutNews, loading: false, error: null, refresh: jest.fn() });
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={{ params: { id: 43 } }} />
            </ThemeProvider>,
        );
        expect(screen.getByTestId("tab-bill").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true }),
        );
        expect(screen.getByTestId("tab-summaries").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: false }),
        );
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByText("Bill 42 Exclusive Article")).toBeNull();
        expect(screen.queryByTestId("related-news-articles")).toBeNull();
    });

    test("renders attributed news testimony under support and oppose cards when present in bill payload", () => {
        const payloadWithTestimonies = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                news_testimonies: [
                    {
                        id: 201,
                        author_name: "Emily Vance",
                        outlet_name: "The Baltimore Banner",
                        stance: "support" as const,
                        url: "https://thebaltimorebanner.com/opinion/support-transit",
                        argument: "Investing in transit expands regional opportunity.",
                    },
                    {
                        id: 202,
                        author_name: null,
                        outlet_name: "The Baltimore Sun",
                        stance: "oppose" as const,
                        url: "https://baltimoresun.com/opinion/editorial/transit-costs",
                        argument: "The proposed funding lacks adequate fiscal guardrails.",
                    },
                ],
            },
        };

        mockUseBill.mockReturnValue({ data: payloadWithTestimonies, loading: false, error: null, refresh: jest.fn() });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByText("By Emily Vance")).toBeTruthy();
        expect(screen.getByText("Investing in transit expands regional opportunity.")).toBeTruthy();
        expect(screen.getByText("The Baltimore Sun Editorial Board")).toBeTruthy();
        expect(screen.getByText("The proposed funding lacks adequate fiscal guardrails.")).toBeTruthy();
        expect(screen.getAllByText("News commentary")).toHaveLength(2);
    });

    test("omits news testimonies cleanly when absent or empty on bill payload", () => {
        const payloadWithoutTestimonies = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                news_testimonies: [],
            },
        };

        mockUseBill.mockReturnValue({
            data: payloadWithoutTestimonies,
            loading: false,
            error: null,
            refresh: jest.fn(),
        });
        wrap(<BillDetailScreen route={route} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByText("News commentary")).toBeNull();
    });

    test("switching bill clears previous bill's news testimonies", () => {
        const payloadWithTestimonies = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                id: 42,
                news_testimonies: [
                    {
                        id: 201,
                        author_name: "Columnist 42",
                        outlet_name: "Outlet 42",
                        stance: "support" as const,
                        url: "https://example.com/42",
                        argument: "Bill 42 unique opinion commentary.",
                    },
                ],
            },
        };
        const payloadWithoutTestimonies = {
            ...fullBillPayload,
            bill: {
                ...fullBillPayload.bill,
                id: 43,
                news_testimonies: [],
            },
        };

        mockUseBill.mockReturnValue({ data: payloadWithTestimonies, loading: false, error: null, refresh: jest.fn() });
        const { rerender } = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByText("By Columnist 42")).toBeTruthy();

        mockUseBill.mockReturnValue({
            data: payloadWithoutTestimonies,
            loading: false,
            error: null,
            refresh: jest.fn(),
        });
        rerender(
            <ThemeProvider initialMode="light">
                <BillDetailScreen route={{ params: { id: 43 } }} />
            </ThemeProvider>,
        );
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByText("By Columnist 42")).toBeNull();
        expect(screen.queryByText("News commentary")).toBeNull();
    });

    describe("the sponsor link", () => {
        test("opens the sponsor's legislator screen in the Legislators tab", () => {
            mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
            withParentNavigate((parentNavigate) => {
                wrap(<BillDetailScreen route={route} />);
                fireEvent.press(screen.getByTestId("bill-header-sponsor"));
                expect(parentNavigate).toHaveBeenCalledTimes(1);
                expect(parentNavigate).toHaveBeenCalledWith("Legislators", {
                    screen: "LegislatorDetail",
                    params: { id: 7 },
                });
            });
        });

        test("is plain text when the bill carries no legislator id", () => {
            const { legislator_id: _omitted, ...billWithoutSponsorId } = fullBillPayload.bill;
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, bill: billWithoutSponsorId },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);

            expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
            expect(screen.getByText(/Sponsored by Alice Q\. Sponsor/)).toBeTruthy();
        });

        test("is absent when the response has no sponsor", () => {
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, sponsor: null },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);

            expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
            expect(screen.queryByText(/Sponsored by/)).toBeNull();
        });
    });

    describe("the Bill tab's hero and source notice", () => {
        test("puts the vote status sentence under the vote buttons", () => {
            mockUseBill.mockReturnValue({
                data: {
                    ...fullBillPayload,
                    bill: {
                        ...fullBillPayload.bill,
                        active: true,
                        vote_date_time_utc: "2026-03-03T17:00:00Z",
                        house_vote_date_time_utc: "2026-03-03T17:00:00Z",
                        senate_vote_date_time_utc: null,
                    },
                },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);

            expectInOrder(["bill-header", "vote-panel", "bill-header-vote-status", "bill-summary-section"]);
            expect(screen.getAllByTestId("bill-header-vote-status")).toHaveLength(1);
            expect(screen.getByText("House voted on March 3, 2026.")).toBeTruthy();
        });

        test("offers the official bill text under the summary", () => {
            mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
            wrap(<BillDetailScreen route={route} />);

            expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.bill.viewOriginalText)).toBeTruthy();
            expect(screen.queryByTestId("summary-no-source-link")).toBeNull();
        });

        test("says the source is unavailable for a bill with no link", () => {
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, bill: { ...fullBillPayload.bill, link: null } },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);

            expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
            expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        });

        test("treats the locale's generic portal page as no source", () => {
            mockUseBootstrap.mockReturnValue({
                bootstrap: {
                    locale: {
                        id: 1,
                        name: "baltimore-maryland-united_states",
                        generic_portal_urls: [fullBillPayload.bill.link],
                    },
                },
                loading: false,
            });
            mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
            wrap(<BillDetailScreen route={route} />);

            expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
            expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        });
    });

    describe("public testimony on the Summaries tab", () => {
        const pillLabel = (count: number, label: string) => `${count} ${label}`;

        test("shows the pills under the organization positions for a signed-in reader", () => {
            signedIn();
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, public_testimony_counts: COUNTS },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expectInOrder(["bill-detail-summaries", "org-positions-section", "public-testimony-section"]);
            expect(screen.getByText(pillLabel(3, PARITY_COPY.publicTestimony.section.supportPill))).toBeTruthy();
            expect(screen.getByText(pillLabel(2, PARITY_COPY.publicTestimony.section.opposePill))).toBeTruthy();
            expect(screen.getByText(pillLabel(1, PARITY_COPY.publicTestimony.section.neutralPill))).toBeTruthy();
            expect(screen.getByTestId("bill-detail-summaries").children).toHaveLength(2);
        });

        test("draws zero nodes when the server sends no counts to a signed-out reader", () => {
            mockUseBill.mockReturnValue({ data: fullBillPayload, loading: false, error: null, refresh: jest.fn() });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("bill-detail-summaries").children).toHaveLength(1);
        });

        test("draws zero nodes when the reader is signed out here even though the response carries counts", () => {
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, public_testimony_counts: COUNTS },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("bill-detail-summaries").children).toHaveLength(1);
        });

        test("draws zero nodes for a signed-in reader when the bill has no letters", () => {
            signedIn();
            mockUseBill.mockReturnValue({
                data: { ...fullBillPayload, public_testimony_counts: { total: 0, support: 0, oppose: 0, neutral: 0 } },
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            wrap(<BillDetailScreen route={route} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("bill-detail-summaries").children).toHaveLength(1);
        });
    });

    // @lat: [[bill-detail-error-recovery#Why the error snapshot stops at the empty state]]
    test("matches snapshot — error state", () => {
        mockUseBill.mockReturnValue({ data: null, loading: false, error: new Error("boom"), refresh: jest.fn() });
        const { toJSON } = wrap(<BillDetailScreen route={route} />);

        const emptyState = findByTestId(toJSON(), "bill-detail-empty");
        expect(emptyState).toBeTruthy();
        expect(emptyState).toMatchSnapshot();
    });
});
