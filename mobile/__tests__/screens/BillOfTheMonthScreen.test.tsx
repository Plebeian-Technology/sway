// --- Fakes. These have to sit at the top of the file, before the imports ---

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

const mockUseSession = jest.fn();
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => mockUseSession(),
}));

const mockUseCastUserVote = jest.fn();
jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => mockUseCastUserVote(),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light", Medium: "Medium", Heavy: "Heavy" },
}));

jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));

jest.mock("react-native-reanimated", () => require("react-native-reanimated/mock"));

const mockUseFocusedSync = jest.fn();
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: (opts: unknown) => mockUseFocusedSync(opts),
}));

// @lat: [[mobile-bill-detail-and-bill-of-the-month-screens#BillOfTheMonthScreen's data source quirks]]
const mockUseBill = jest.fn();
jest.mock("../../src/hooks/useBill", () => ({
    useBill: (id: number) => mockUseBill(id),
}));

// Replace SkeletonCard so the tests never pull in the native animation code.
jest.mock("../../src/components/SkeletonCard", () => {
    const ReactMod = require("react");
    const RNMod = require("react-native");
    return {
        SkeletonCard: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
    };
});

import React from "react";
import { act, fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import BillOfTheMonthScreen from "../../src/screens/BillOfTheMonthScreen";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const FULL_BOTM = {
    id: 1,
    external_id: "HB1234",
    external_version: "1",
    title: "Open Records Act",
    summary: "A bill to improve transparency in government records.",
    summary_ai_unreviewed: false,
    link: "https://mgaleg.maryland.gov/bills/HB1234",
    chamber: "House",
    category: "government",
    status: "committee",
    active: true,
    scheduled_release_date_utc: null,
    audio_bucket_path: null,
    audio_by_line: null,
    vote_date_time_utc: null,
    introduced_date_time_utc: "2026-01-15T00:00:00Z",
    house_vote_date_time_utc: null,
    senate_vote_date_time_utc: null,
    vote: null,
    categories: ["Government"],
    legislator_id: 7,
    sway_locale_id: 1,
    created_at: "2026-01-15T00:00:00Z",
    user_vote: null,
};

const COUNTS = { total: 6, support: 3, oppose: 2, neutral: 1 };

const BOTM_PAGE = {
    bill: { ...FULL_BOTM, related_articles: [], news_testimonies: [] },
    sponsor: { full_name: "Sen. Smith" },
    user_vote: null,
    bill_score: {
        id: 3,
        bill_id: 1,
        for: 42,
        against: 18,
        comparison_suppressed: false,
        voters_needed: 0,
        districts: [
            {
                bill_score_id: 3,
                district: { name: "MD1", number: 1, region_code: "MD" },
                comparison_suppressed: false,
                for_percent: 67,
                against_percent: 33,
                at_large: false,
            },
            {
                bill_score_id: 3,
                district: { name: "MD2", number: 2, region_code: "MD" },
                comparison_suppressed: false,
                for_percent: 31,
                against_percent: 69,
                at_large: false,
            },
        ],
    },
    districts: [{ name: "MD2", number: 2, region_code: "MD" }],
    organizations: [
        {
            id: 1,
            support: "FOR" as const,
            organization: { name: "Supporters Org" },
            summary: "We support this because it improves access.",
        },
    ],
    public_testimony_counts: COUNTS as typeof COUNTS | null,
};

const pageFor = (bill: Record<string, unknown>) => ({ ...BOTM_PAGE, bill: { ...BOTM_PAGE.bill, ...bill } });

const serveDetailPages = (pages: Record<number, unknown>) => {
    const refresh = jest.fn();
    mockUseBill.mockImplementation((id: number) => ({ data: pages[id] ?? null, loading: false, error: null, refresh }));
};

const LOCALE = { id: 1, name: "baltimore-maryland-united_states" };
const SWAY_LOCALES = [
    { id: 1, name: "Baltimore City, MD" },
    { id: 2, name: "Maryland" },
];

function makeBootstrap(overrides: Record<string, unknown> = {}) {
    return {
        bootstrap: {
            bill_of_the_month: FULL_BOTM,
            locale: LOCALE,
            sway_locales: SWAY_LOCALES,
            ...overrides,
        },
        loading: false,
        error: null,
        refetch: jest.fn(),
        needsUpdate: false,
    };
}

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

function makeNav() {
    return { navigate: jest.fn() };
}

describe("BillOfTheMonthScreen", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseSession.mockReset();
        mockUseCastUserVote.mockReset();
        mockUseFocusedSync.mockReset();

        mockUseSession.mockReturnValue({ isAuthenticated: true });
        mockUseCastUserVote.mockReturnValue({ submit: jest.fn(), isOnline: true, isResolved: true });
        mockUseBill.mockReset();
        mockUseBill.mockReturnValue({ data: BOTM_PAGE, loading: false, error: null, refresh: jest.fn() });
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    test("fetches the featured bill's detail response, because bootstrap carries only the bill itself", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(mockUseBill).toHaveBeenCalledWith(FULL_BOTM.id);
        expect(screen.getByText(/Sponsored by Sen\. Smith/)).toBeTruthy();
    });

    test("the Votes tab reads the locale score and the Summaries tab the organization positions from the detail response", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.getByText(/For: 42/)).toBeTruthy();
        expect(screen.getByText(/Against: 18/)).toBeTruthy();

        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByText("Supporters Org")).toBeTruthy();
    });

    test("the Bill tab paints from bootstrap alone while the detail response is still loading", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        mockUseBill.mockReturnValue({ data: null, loading: true, error: null, refresh: jest.fn() });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByTestId("bill-header")).toBeTruthy();
        expect(screen.getByText("Open Records Act")).toBeTruthy();
        expect(screen.getByTestId("bill-summary-section")).toBeTruthy();
        expect(screen.getByTestId("vote-panel")).toBeTruthy();
    });

    test("while the detail response is loading the Votes and Summaries tabs show skeletons, not zeros or an empty claim", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        mockUseBill.mockReturnValue({ data: null, loading: true, error: null, refresh: jest.fn() });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.getByTestId("votes-skeleton")).toBeTruthy();
        expect(screen.queryByText(/For: 0/)).toBeNull();
        expect(screen.queryByTestId("bill-score-bar")).toBeNull();

        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("summaries-skeleton")).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.org.noSupport)).toBeNull();
    });

    test("when the detail response fails the Votes tab offers a retry that reloads the bill", () => {
        const refresh = jest.fn();
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        mockUseBill.mockReturnValue({ data: null, loading: false, error: new Error("boom"), refresh });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByTestId("bill-header")).toBeTruthy();
        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.getByText(PARITY_COPY.bill.detailError)).toBeTruthy();
        fireEvent.press(screen.getByTestId("votes-detail-error-cta"));
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("a failed first load keeps the retry row while the next poll is loading, instead of flickering to a skeleton", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        mockUseBill.mockReturnValue({ data: null, loading: true, error: new Error("boom"), refresh: jest.fn() });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.getByTestId("votes-detail-error")).toBeTruthy();
        expect(screen.queryByTestId("votes-skeleton")).toBeNull();

        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("summaries-detail-error")).toBeTruthy();
        expect(screen.queryByTestId("summaries-skeleton")).toBeNull();
    });

    test("a reload after the detail response has arrived keeps the tabs filled", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        mockUseBill.mockReturnValue({
            data: BOTM_PAGE,
            loading: true,
            error: new Error("offline"),
            refresh: jest.fn(),
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.queryByTestId("votes-skeleton")).toBeNull();
        expect(screen.queryByTestId("votes-detail-error")).toBeNull();
        expect(screen.getByText(/For: 42/)).toBeTruthy();
    });

    test("the Votes tab marks the reader's own district from the detail response", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        expect(screen.getByTestId("district-votes-reader")).toBeTruthy();
    });

    test("the Bill tab carries information about the bill, not only the vote buttons", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByText("A bill to improve transparency in government records.")).toBeTruthy();
        expect(screen.getByText("Government")).toBeTruthy();
        expect(screen.getByTestId("bill-header-status")).toBeTruthy();
        expect(screen.getByTestId("bill-header-vote-status")).toBeTruthy();
    });

    test("a pull to refresh and the poll both reload the bill detail and bootstrap", () => {
        const refetch = jest.fn();
        const billRefresh = jest.fn();
        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), refetch });
        mockUseBill.mockReturnValue({ data: BOTM_PAGE, loading: false, error: null, refresh: billRefresh });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        act(() => {
            screen.getByTestId("botm-scroll").props.refreshControl.props.onRefresh();
        });
        expect(refetch).toHaveBeenCalledTimes(1);
        expect(billRefresh).toHaveBeenCalledTimes(1);

        const refreshes = new Set<() => void>(
            mockUseFocusedSync.mock.calls.map((call: [{ refresh: () => void }]) => call[0].refresh),
        );
        expect(refreshes.size).toBe(2);
        act(() => {
            refreshes.forEach((refresh) => refresh());
        });
        expect(refetch).toHaveBeenCalledTimes(2);
        expect(billRefresh).toHaveBeenCalledTimes(2);
    });

    test("opens on the Bill tab: the hero card and summary show and the Votes and Summaries sections do not", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByTestId("botm-hero")).toBeTruthy();
        expect(screen.getByTestId("bill-header")).toBeTruthy();
        expect(screen.getByTestId("vote-panel")).toBeTruthy();
        expect(screen.getByTestId("bill-summary-section")).toBeTruthy();
        expect(screen.queryByTestId("bill-score-bar")).toBeNull();
        expect(screen.queryByTestId("take-next-step")).toBeNull();
        expect(screen.queryByTestId("org-positions-section")).toBeNull();
    });

    test("the Votes tab shows VotePanel, BillScoreBar, DistrictVotesPanel and HearingTestimonySection", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));

        expect(screen.getByTestId("vote-panel-for")).toBeTruthy();
        expect(screen.getByTestId("bill-score-bar")).toBeTruthy();
        expect(screen.getByTestId("district-votes-panel")).toBeTruthy();
        expect(screen.getByTestId("take-next-step")).toBeTruthy();
        expect(screen.queryByTestId("botm-hero")).toBeNull();
        expect(screen.queryByTestId("bill-summary-section")).toBeNull();
    });

    test("the Summaries tab shows OrgPositionsSection, and the summary stays on the Bill tab", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByTestId("bill-summary-section")).toBeNull();
        expect(screen.queryByTestId("botm-hero")).toBeNull();
        expect(screen.queryByTestId("take-next-step")).toBeNull();
    });

    test("a vote cast from the Votes tab reloads bootstrap and the bill detail once after 1500ms", async () => {
        jest.useFakeTimers();
        const refetch = jest.fn();
        const billRefresh = jest.fn();
        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), refetch });
        mockUseBill.mockReturnValue({ data: BOTM_PAGE, loading: false, error: null, refresh: billRefresh });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));
        await act(async () => {
            fireEvent.press(screen.getByTestId("vote-panel-for"));
        });
        await act(async () => {
            fireEvent.press(screen.getByTestId("vote-panel-confirm-submit"));
        });
        act(() => {
            jest.advanceTimersByTime(1499);
        });
        expect(refetch).not.toHaveBeenCalled();
        expect(billRefresh).not.toHaveBeenCalled();

        act(() => {
            jest.advanceTimersByTime(1);
        });
        expect(refetch).toHaveBeenCalledTimes(1);
        expect(billRefresh).toHaveBeenCalledTimes(1);
    });

    test("the selected tab survives a bootstrap refetch of the same bill", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        fireEvent.press(screen.getByTestId("tab-votes"));

        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), loading: true });
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );

        expect(screen.getByTestId("tab-votes").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true }),
        );
        expect(screen.getByTestId("take-next-step")).toBeTruthy();
    });

    test("renders SwayLocalePickerSheet trigger at the TOP of the scroll view (before bill-header)", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        const trigger = screen.getByTestId("locale-picker-trigger");
        const header = screen.getByTestId("bill-header");
        expect(trigger).toBeTruthy();
        expect(header).toBeTruthy();
    });

    test("D-13 sections: renders the locale-picker-trigger and the tab strip, and each of the Bill, Votes and Summaries tabs shows its sections", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        ["locale-picker-trigger", "broadside-tab-strip", "bill-header", "vote-panel", "bill-summary-section"].forEach(
            (id) => expect(screen.getByTestId(id)).toBeTruthy(),
        );
        fireEvent.press(screen.getByTestId("tab-votes"));
        ["vote-panel", "take-next-step"].forEach((id) => expect(screen.getByTestId(id)).toBeTruthy());
        fireEvent.press(screen.getByTestId("tab-summaries"));
        ["org-positions-section"].forEach((id) => expect(screen.getByTestId(id)).toBeTruthy());
    });

    test("calls useFocusedSync with { pollMs: 15000 }", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(mockUseFocusedSync).toHaveBeenCalled();
        const arg = mockUseFocusedSync.mock.calls[0][0] as { pollMs: number; refresh: () => void };
        expect(arg.pollMs).toBe(15000);
        expect(typeof arg.refresh).toBe("function");
    });

    test("renders EmptyState with PARITY_COPY.botmEmpty when bill_of_the_month is null", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: {
                bill_of_the_month: null,
                locale: LOCALE,
                sway_locales: SWAY_LOCALES,
            },
            loading: false,
            error: null,
            refetch: jest.fn(),
            needsUpdate: false,
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByTestId("botm-empty")).toBeTruthy();
        expect(screen.getByText("No Bill of the Month is featured right now. Check back soon.")).toBeTruthy();
    });

    test("renders EmptyState when bill_of_the_month.title is undefined", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: {
                bill_of_the_month: { id: 1 },
                locale: LOCALE,
                sway_locales: SWAY_LOCALES,
            },
            loading: false,
            error: null,
            refetch: jest.fn(),
            needsUpdate: false,
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByTestId("botm-empty")).toBeTruthy();
    });

    test("VotePanel onVoted triggers setTimeout(refreshBootstrap, 1500ms) with cleanup", () => {
        jest.useFakeTimers();
        const refetch = jest.fn();
        mockUseBootstrap.mockReturnValue({
            ...makeBootstrap(),
            refetch,
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        // useFocusedSync's refresh argument is the cached refetch, and
        // handleVoted wraps refreshBootstrap in a setTimeout. Rather than driving
        // VotePanel's onVoted directly, this checks the wiring is in place.
        expect(mockUseFocusedSync).toHaveBeenCalled();

        jest.useRealTimers();
    });

    test("main ScrollView has testID=botm-scroll (PTR enabled)", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(screen.getByTestId("botm-scroll")).toBeTruthy();
    });

    test("a bootstrap refetch the reader did not pull for leaves the refresh spinner hidden", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), loading: true });
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );

        expect(screen.getByTestId("botm-scroll").props.refreshControl.props.refreshing).toBe(false);
    });

    test("a pull to refresh shows the refresh spinner until bootstrap loading ends", () => {
        const refetch = jest.fn();
        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), refetch });
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        const refreshing = () => screen.getByTestId("botm-scroll").props.refreshControl.props.refreshing;

        act(() => {
            screen.getByTestId("botm-scroll").props.refreshControl.props.onRefresh();
        });
        expect(refetch).toHaveBeenCalledTimes(1);
        expect(refreshing()).toBe(true);

        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), refetch, loading: true });
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );
        expect(refreshing()).toBe(true);

        mockUseBootstrap.mockReturnValue({ ...makeBootstrap(), refetch, loading: false });
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );
        expect(refreshing()).toBe(false);
    });

    // Checked by structure instead of a snapshot: the theme context objects refer back to
    // themselves, and the snapshot formatter runs out of stack on a tree this deep.
    test("full render — all 8 D-13 testIDs present across the three tabs (structural snapshot evidence)", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        const expectedTestIDsByTab = {
            "tab-bill": ["botm-scroll", "locale-picker-trigger", "bill-header", "vote-panel", "bill-summary-section"],
            "tab-votes": ["vote-panel", "bill-score-bar", "district-votes-panel", "take-next-step"],
            "tab-summaries": ["org-positions-section"],
        };
        Object.entries(expectedTestIDsByTab).forEach(([tab, ids]) => {
            fireEvent.press(screen.getByTestId(tab));
            ids.forEach((id) => expect(screen.getByTestId(id)).toBeTruthy());
        });
    });

    describe("the sponsor link", () => {
        test("opens the sponsor's legislator screen in the Legislators tab, using the id the bootstrap bill carries", () => {
            mockUseBootstrap.mockReturnValue(makeBootstrap());
            const parentNavigate = jest.fn();
            const navigation = jest.requireMock<typeof import("@react-navigation/native")>("@react-navigation/native");
            const spy = jest
                .spyOn(navigation, "useNavigation")
                .mockReturnValue({ getParent: () => ({ navigate: parentNavigate }) } as never);
            try {
                wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
                fireEvent.press(screen.getByTestId("bill-header-sponsor"));
                expect(parentNavigate).toHaveBeenCalledTimes(1);
                expect(parentNavigate).toHaveBeenCalledWith("Legislators", {
                    screen: "LegislatorDetail",
                    params: { id: FULL_BOTM.legislator_id },
                });
            } finally {
                spy.mockRestore();
            }
        });

        test("waits for the detail response, which is what names the sponsor", () => {
            mockUseBootstrap.mockReturnValue(makeBootstrap());
            mockUseBill.mockReturnValue({ data: null, loading: true, error: null, refresh: jest.fn() });
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

            expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
            expect(screen.queryByText(/Sponsored by/)).toBeNull();
        });

        test("is plain text when the featured bill has no legislator id", () => {
            const { legislator_id: _omitted, ...withoutSponsorId } = FULL_BOTM;
            mockUseBootstrap.mockReturnValue(makeBootstrap({ bill_of_the_month: withoutSponsorId }));
            serveDetailPages({
                1: { ...BOTM_PAGE, bill: { ...withoutSponsorId, related_articles: [], news_testimonies: [] } },
            });
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

            expect(screen.queryByTestId("bill-header-sponsor")).toBeNull();
            expect(screen.getByText(/Sponsored by Sen\. Smith/)).toBeTruthy();
        });
    });

    describe("the Bill tab's hero and source notice", () => {
        test("puts the vote status sentence under the vote buttons", () => {
            mockUseBootstrap.mockReturnValue(
                makeBootstrap({
                    bill_of_the_month: { ...FULL_BOTM, vote_date_time_utc: "2026-03-03T17:00:00Z" },
                }),
            );
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

            const ids = screen.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);
            expect(ids.indexOf("bill-header-vote-status")).toBeGreaterThan(ids.indexOf("vote-panel"));
            expect(screen.getAllByTestId("bill-header-vote-status")).toHaveLength(1);
        });

        test("offers the official bill text from the bootstrap bill, before the detail response arrives", () => {
            mockUseBootstrap.mockReturnValue(makeBootstrap());
            mockUseBill.mockReturnValue({ data: null, loading: true, error: null, refresh: jest.fn() });
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

            expect(screen.getByTestId("bill-source-text-link")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.bill.viewOriginalText)).toBeTruthy();
        });

        test("says the source is unavailable when the featured bill has no link", () => {
            mockUseBootstrap.mockReturnValue(
                makeBootstrap({
                    bill_of_the_month: { ...FULL_BOTM, link: null },
                }),
            );
            serveDetailPages({ 1: pageFor({ link: null }) });
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

            expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
            expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        });

        test("treats the locale's generic portal page as no source", () => {
            mockUseBootstrap.mockReturnValue(
                makeBootstrap({ locale: { ...LOCALE, generic_portal_urls: [FULL_BOTM.link] } }),
            );
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

            expect(screen.getByText(PARITY_COPY.bill.officialSourceUnavailable)).toBeTruthy();
            expect(screen.queryByTestId("bill-source-text-link")).toBeNull();
        });
    });

    describe("public testimony on the Summaries tab", () => {
        const pill = (count: number, label: string) => `${count} ${label}`;

        test("shows the pills under the organization positions, from the detail response", () => {
            mockUseBootstrap.mockReturnValue(makeBootstrap());
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            const ids = screen.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);
            expect(ids.indexOf("public-testimony-section")).toBeGreaterThan(ids.indexOf("org-positions-section"));
            expect(screen.getByText(pill(3, PARITY_COPY.publicTestimony.section.supportPill))).toBeTruthy();
            expect(screen.getByText(pill(2, PARITY_COPY.publicTestimony.section.opposePill))).toBeTruthy();
            expect(screen.getByText(pill(1, PARITY_COPY.publicTestimony.section.neutralPill))).toBeTruthy();
            expect(screen.getByTestId("botm-summaries").children).toHaveLength(2);
        });

        test("ignores counts on the bootstrap bill: the detail response is the only source", () => {
            const staleCounts = { total: 99, support: 90, oppose: 5, neutral: 4 };
            mockUseBootstrap.mockReturnValue(
                makeBootstrap({
                    bill_of_the_month: { ...FULL_BOTM, public_testimony_counts: staleCounts },
                }),
            );
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByText(pill(3, PARITY_COPY.publicTestimony.section.supportPill))).toBeTruthy();
            expect(screen.queryByText(pill(90, PARITY_COPY.publicTestimony.section.supportPill))).toBeNull();
        });

        test("draws nothing from bootstrap counts while the detail response is loading", () => {
            const staleCounts = { total: 99, support: 90, oppose: 5, neutral: 4 };
            mockUseBootstrap.mockReturnValue(
                makeBootstrap({
                    bill_of_the_month: { ...FULL_BOTM, public_testimony_counts: staleCounts },
                }),
            );
            mockUseBill.mockReturnValue({ data: null, loading: true, error: null, refresh: jest.fn() });
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByTestId("summaries-skeleton")).toBeTruthy();
            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
        });

        test("draws zero nodes when the server sends no counts to a signed-out reader", () => {
            mockUseSession.mockReturnValue({ isAuthenticated: false });
            mockUseBootstrap.mockReturnValue(makeBootstrap());
            serveDetailPages({ 1: { ...BOTM_PAGE, public_testimony_counts: null } });
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("botm-summaries").children).toHaveLength(1);
        });

        test("draws zero nodes when the reader is signed out here even though the response carries counts", () => {
            mockUseSession.mockReturnValue({ isAuthenticated: false });
            mockUseBootstrap.mockReturnValue(makeBootstrap());
            wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByTestId("public-testimony-section")).toBeNull();
            expect(screen.getByTestId("botm-summaries").children).toHaveLength(1);
        });
    });

    test("matches snapshot — empty state", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: {
                bill_of_the_month: null,
                locale: LOCALE,
                sway_locales: SWAY_LOCALES,
            },
            loading: false,
            error: null,
            refetch: jest.fn(),
            needsUpdate: false,
        });
        const { toJSON } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        expect(toJSON()).toMatchSnapshot();
    });

    test("useFocusedSync is called once for bootstrap and once for the bill detail per render, each with a stable refresh (Pitfall 2)", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);

        expect(mockUseFocusedSync).toHaveBeenCalledTimes(2);

        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );

        expect(mockUseFocusedSync).toHaveBeenCalledTimes(4);
        const refreshAt = (index: number) => mockUseFocusedSync.mock.calls[index][0].refresh as () => void;
        expect(refreshAt(0)).toBe(refreshAt(2));
        expect(refreshAt(1)).toBe(refreshAt(3));
    });

    test("the detail sync keeps one refresh function even when useBill hands back a new result object every render", () => {
        const billRefresh = jest.fn();
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        mockUseBill.mockImplementation(() => ({ data: BOTM_PAGE, loading: false, error: null, refresh: billRefresh }));
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );

        const refreshes = new Set(
            mockUseFocusedSync.mock.calls.map((call: [{ refresh: () => void }]) => call[0].refresh),
        );
        expect(refreshes.size).toBe(2);
    });

    test("renders SkeletonCard while loading (no botm yet)", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: null,
            loading: true,
            error: null,
            refetch: jest.fn(),
            needsUpdate: false,
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        expect(screen.getByTestId("botm-loading")).toBeTruthy();
    });

    test("renders OfflineBanner when offline (isOnline=false from useCastUserVote)", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        // The screen only shows OfflineBanner when `!isOnline && isResolved`.
        mockUseCastUserVote.mockReturnValue({ submit: jest.fn(), isOnline: false, isResolved: true });

        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        expect(screen.getByTestId("offline-banner")).toBeTruthy();
        expect(screen.getByTestId("vote-panel-for").props.accessibilityHint).toBe(
            "You're offline — votes require a connection.",
        );
        expect(screen.getByTestId("vote-panel-against").props.accessibilityHint).toBe(
            "You're offline — votes require a connection.",
        );
    });

    test("renders RelatedNewsArticles section when the bill detail has related_articles", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        serveDetailPages({
            1: pageFor({
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
            }),
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("related-news-articles")).toBeTruthy();
        expect(screen.getByText("Transit Overhaul Advances")).toBeTruthy();
        expect(screen.getByText("The Baltimore Sun")).toBeTruthy();
    });

    test("omits RelatedNewsArticles section when the bill detail has empty related_articles", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        serveDetailPages({ 1: pageFor({ related_articles: [] }) });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByTestId("related-news-articles")).toBeNull();
    });

    test("switching locale in LocalePickerSheet updates featured bill and clears previous locale's related articles", () => {
        const botmLocale1 = { ...FULL_BOTM, id: 1 };
        const botmLocale2 = { ...FULL_BOTM, id: 2, title: "Locale 2 Bill Without News" };
        serveDetailPages({
            1: pageFor({
                id: 1,
                related_articles: [
                    {
                        id: 10,
                        title: "Locale 1 Exclusive Article",
                        outlet_name: "The Baltimore Sun",
                        author_name: null,
                        published_at: null,
                        article_kind: "reporting",
                        match_kind: "direct",
                        url: "https://example.com/story1",
                    },
                ],
            }),
            2: pageFor({ id: 2, title: "Locale 2 Bill Without News", related_articles: [] }),
        });

        mockUseBootstrap.mockReturnValue(makeBootstrap({ bill_of_the_month: botmLocale1 }));
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByText("Locale 1 Exclusive Article")).toBeTruthy();

        mockUseBootstrap.mockReturnValue(makeBootstrap({ bill_of_the_month: botmLocale2 }));
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
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
        expect(screen.queryByText("Locale 1 Exclusive Article")).toBeNull();
        expect(screen.queryByTestId("related-news-articles")).toBeNull();
    });

    test("renders attributed news testimony under support and oppose when present in the bill detail", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        serveDetailPages({
            1: pageFor({
                news_testimonies: [
                    {
                        id: 301,
                        author_name: "Emily Vance",
                        outlet_name: "The Baltimore Banner",
                        stance: "support" as const,
                        url: "https://thebaltimorebanner.com/opinion/support-transit",
                        argument: "Investing in transit expands regional opportunity.",
                    },
                    {
                        id: 302,
                        author_name: null,
                        outlet_name: "The Baltimore Sun",
                        stance: "oppose" as const,
                        url: "https://baltimoresun.com/opinion/editorial/transit-costs",
                        argument: "The proposed funding lacks adequate fiscal guardrails.",
                    },
                ],
            }),
        });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByText("By Emily Vance")).toBeTruthy();
        expect(screen.getByText("Investing in transit expands regional opportunity.")).toBeTruthy();
        expect(screen.getByText("The Baltimore Sun Editorial Board")).toBeTruthy();
        expect(screen.getByText("The proposed funding lacks adequate fiscal guardrails.")).toBeTruthy();
        expect(screen.getAllByText("News commentary")).toHaveLength(2);
    });

    test("omits news testimonies when the bill detail has empty news_testimonies", () => {
        mockUseBootstrap.mockReturnValue(makeBootstrap());
        serveDetailPages({ 1: pageFor({ news_testimonies: [] }) });
        wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByText("News commentary")).toBeNull();
    });

    test("switching locale in LocalePickerSheet updates featured bill and clears previous locale's news testimonies", () => {
        const botmLocale1 = { ...FULL_BOTM, id: 1 };
        const botmLocale2 = { ...FULL_BOTM, id: 2, title: "Locale 2 Bill Without News" };
        serveDetailPages({
            1: pageFor({
                id: 1,
                news_testimonies: [
                    {
                        id: 301,
                        author_name: "Locale 1 Columnist",
                        outlet_name: "Locale 1 Herald",
                        stance: "support" as const,
                        url: "https://example.com/l1",
                        argument: "Locale 1 unique opinion argument.",
                    },
                ],
            }),
            2: pageFor({ id: 2, title: "Locale 2 Bill Without News", news_testimonies: [] }),
        });

        mockUseBootstrap.mockReturnValue(makeBootstrap({ bill_of_the_month: botmLocale1 }));
        const { rerender } = wrap(<BillOfTheMonthScreen navigation={makeNav()} />);
        fireEvent.press(screen.getByTestId("tab-summaries"));
        expect(screen.getByText("By Locale 1 Columnist")).toBeTruthy();

        mockUseBootstrap.mockReturnValue(makeBootstrap({ bill_of_the_month: botmLocale2 }));
        rerender(
            <ThemeProvider initialMode="light">
                <BillOfTheMonthScreen navigation={makeNav()} />
            </ThemeProvider>,
        );
        fireEvent.press(screen.getByTestId("tab-summaries"));

        expect(screen.getByTestId("org-positions-section")).toBeTruthy();
        expect(screen.queryByText("By Locale 1 Columnist")).toBeNull();
        expect(screen.queryByText("News commentary")).toBeNull();
    });
});
