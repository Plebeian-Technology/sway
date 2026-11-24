// @lat: [[mobile-jest-first-pass-test-notes#Mobile Jest test notes]]

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

const mockUseLegislators = jest.fn();
jest.mock("../../src/hooks/useLegislators", () => ({
    useLegislators: (...args: unknown[]) => mockUseLegislators(...args),
}));

const mockUseLegislator = jest.fn();
jest.mock("../../src/hooks/useLegislator", () => ({
    useLegislator: (...args: unknown[]) => mockUseLegislator(...args),
}));

jest.mock("../../src/hooks/useFocusedSync", () => ({ useFocusedSync: jest.fn() }));

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(async () => ({})),
        post: jest.fn(async () => ({})),
        patch: jest.fn(async () => ({})),
        delete: jest.fn(async () => undefined),
    },
}));

jest.mock("../../src/components/LegislatorChartsPanel", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        LegislatorChartsPanel: ({ testID }: { testID?: string; score?: unknown }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "legislator-charts-panel" }),
        default: ({ testID }: { testID?: string; score?: unknown }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "legislator-charts-panel" }),
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

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import LegislatorDetailScreen from "../../src/screens/LegislatorDetailScreen";
import { useFocusedSync } from "../../src/hooks/useFocusedSync";
import { formatReleaseMonth } from "../../src/components/legislators/LegislatorBillOfTheMonthRecord";
import type {
    ILegislatorBillOfTheMonthVote,
    ILegislatorTermEntry,
    IHistoricalScoreExplanation,
} from "../../src/types/legislator";

const LOCALES = [{ id: 1, name: "baltimore-maryland-united_states" }];

const BASE_BOOTSTRAP = {
    locale: { id: 1, name: "baltimore-maryland-united_states" },
    sway_locales: LOCALES,
    current_user: { id: 1 },
};

const BASE_SCORE = {
    count_agreed: 8,
    count_disagreed: 2,
    count_no_legislator_vote: 1,
    count_legislator_abstained: 0,
};

const LEG_FULL = {
    id: 99,
    full_name: "Carol Legislator",
    title: "Senator",
    party: "Democrat",
    email: "carol@example.gov",
    phone: "410-555-1234",
    photo_url: null,
    user_legislator_score: BASE_SCORE,
    lifetime_score: BASE_SCORE,
    active: true,
};

const sampleDistrictScore = {
    count_agreed: 8,
    count_disagreed: 2,
    count_no_legislator_vote: 1,
    count_legislator_abstained: 0,
    comparison_suppressed: false,
    agreed_percent: 73,
    disagreed_percent: 18,
    no_legislator_vote_percent: 9,
    legislator_abstained_percent: 0,
};

const sampleLocaleScore = {
    count_agreed: 18,
    count_disagreed: 6,
    count_no_legislator_vote: 2,
    count_legislator_abstained: 0,
    comparison_suppressed: false,
    agreed_percent: 69,
    disagreed_percent: 23,
    no_legislator_vote_percent: 8,
    legislator_abstained_percent: 0,
};

const sampleUserScore = {
    count_agreed: 4,
    count_disagreed: 1,
    count_no_legislator_vote: 0,
    count_legislator_abstained: 0,
};

const sampleCorrectionExplanation: IHistoricalScoreExplanation = {
    title: "Official Term Date Correction",
    body: "Service dates adjusted per official Maryland General Assembly records. Recalculated 2 votes.",
    delta: 2,
    score_type: "term_202",
};

const sampleTerm2025: ILegislatorTermEntry = {
    id: 101,
    session_label: "119th Congress",
    term_start_year: 2025,
    term_end_year: 2027,
    began_on: "2025-01-03",
    ended_on: null,
    district_name: "MD3",
    is_executive: false,
    active: true,
    district_score: sampleDistrictScore,
    locale_score: sampleLocaleScore,
    user_score: sampleUserScore,
    correction_explanation: null,
};

const sampleTerm2021: ILegislatorTermEntry = {
    id: 102,
    session_label: "117th Congress",
    term_start_year: 2021,
    term_end_year: 2023,
    began_on: "2021-01-03",
    ended_on: "2023-01-03",
    district_name: "MD3",
    is_executive: false,
    active: false,
    district_score: sampleDistrictScore,
    locale_score: sampleLocaleScore,
    user_score: null,
    correction_explanation: sampleCorrectionExplanation,
};

const sampleExecutiveTerm: ILegislatorTermEntry = {
    id: 103,
    session_label: "2020–2024 Mayoral Term",
    term_start_year: 2020,
    term_end_year: 2024,
    began_on: "2020-12-08",
    ended_on: "2024-12-10",
    district_name: null,
    is_executive: true,
    active: false,
    district_score: null,
    locale_score: null,
    user_score: null,
    correction_explanation: null,
};

function makeRoute(id: number) {
    return { params: { id } };
}

function mockLegislators(legislators: unknown[], loading = false) {
    mockUseLegislators.mockReturnValue({
        data: legislators,
        loading,
        error: null,
        refresh: jest.fn(),
        isOnline: true,
    });
}

function mockLegislatorDetail(legislator: unknown, loading = false, error: Error | null = null) {
    mockUseLegislator.mockReturnValue({ data: legislator, loading, error, refresh: jest.fn() });
}

const BOTM_VOTES: ILegislatorBillOfTheMonthVote[] = [
    {
        bill_id: 101,
        external_id: "cb26-0001",
        title: "Clean Water Act",
        scheduled_release_date_utc: "2026-10-01",
        status: "passed",
        legislator_vote: "FOR",
        user_vote: "FOR",
        alignment: "agreed",
    },
    {
        bill_id: 102,
        external_id: "cb26-0002",
        title: "Parking Reform",
        scheduled_release_date_utc: "2026-09-01",
        status: null,
        legislator_vote: "AGAINST",
        user_vote: "FOR",
        alignment: "disagreed",
    },
    {
        bill_id: 103,
        external_id: "cb26-0003",
        title: "Library Hours",
        scheduled_release_date_utc: "2026-08-01",
        status: null,
        legislator_vote: "ABSTAIN",
        user_vote: null,
        alignment: null,
    },
    {
        bill_id: 104,
        external_id: "cb26-0004",
        title: "Tree Canopy",
        scheduled_release_date_utc: "2026-07-01",
        status: null,
        legislator_vote: null,
        user_vote: "AGAINST",
        alignment: null,
    },
];

describe("LegislatorDetailScreen Bill of the Month voting record", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseLegislators.mockReset();
        mockUseLegislator.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
        mockLegislators([LEG_FULL]);
    });

    test("fetches the detail legislator and renders every vote kind with user votes and alignment", () => {
        mockLegislatorDetail({ ...LEG_FULL, terms: [sampleTerm2025], bill_of_the_month_votes: BOTM_VOTES });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);

        expect(mockUseLegislator).toHaveBeenCalledWith(99);
        expect(screen.getByText("Bill of the Month Voting Record")).toBeTruthy();

        const rows = screen.getAllByTestId(/^botm-record-row-/);
        expect(rows).toHaveLength(4);
        expect(screen.getByTestId("botm-record-row-101")).toHaveTextContent(/Oct 2026/);
        expect(screen.getByTestId("botm-record-row-101")).toHaveTextContent(/CB26-0001/);
        expect(screen.getByTestId("botm-record-row-101")).toHaveTextContent(/Clean Water Act/);

        const legislatorVotes = screen.getAllByTestId(/^botm-legislator-vote-/);
        expect(legislatorVotes).toHaveLength(4);
        expect(screen.getByTestId("botm-legislator-vote-101")).toHaveTextContent("For");
        expect(screen.getByTestId("botm-legislator-vote-102")).toHaveTextContent("Against");
        expect(screen.getByTestId("botm-legislator-vote-103")).toHaveTextContent("Abstain");
        expect(screen.getByTestId("botm-legislator-vote-104")).toHaveTextContent("No vote recorded");

        expect(screen.getByTestId("botm-user-vote-101")).toHaveTextContent("For");
        expect(screen.getByTestId("botm-user-vote-103")).toHaveTextContent("Not voted");
        expect(screen.getByTestId("botm-user-vote-104")).toHaveTextContent("Against");

        const alignments = screen.getAllByTestId(/^botm-alignment-/);
        expect(alignments).toHaveLength(2);
        expect(screen.getByTestId("botm-alignment-101")).toHaveTextContent("Agreed");
        expect(screen.getByTestId("botm-alignment-102")).toHaveTextContent("Disagreed");
    });

    test("tapping a bill row navigates to BillDetail", () => {
        mockLegislatorDetail({ ...LEG_FULL, terms: [sampleTerm2025], bill_of_the_month_votes: BOTM_VOTES });
        const navigate = jest.fn();
        render(<LegislatorDetailScreen route={makeRoute(99)} navigation={{ navigate }} />);
        fireEvent.press(screen.getByRole("link", { name: /Clean Water Act/ }));
        expect(navigate).toHaveBeenCalledWith("BillDetail", { id: 101 });
    });

    test("shows the empty message when a legislative representative has no released bills", () => {
        mockLegislatorDetail({ ...LEG_FULL, terms: [sampleTerm2025], bill_of_the_month_votes: [] });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("No Bills of the Month have come before this representative yet.")).toBeTruthy();
    });

    test("renders the voting record for an executive", () => {
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-row-101")).toBeTruthy();
    });

    test("shows the empty message for an executive when bill_of_the_month_votes is empty array", () => {
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }],
            bill_of_the_month_votes: [],
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByText("No Bills of the Month have come before this representative yet.")).toBeTruthy();
        expect(screen.queryAllByTestId(/^botm-record-row-/)).toHaveLength(0);
    });

    test("shows skeleton while detail request loads for an executive", () => {
        mockLegislators([{ ...LEG_FULL, terms: [{ ...sampleExecutiveTerm, active: true }] }]);
        mockLegislatorDetail(null, true);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-skeleton")).toBeTruthy();
        expect(screen.queryByText("No Bills of the Month have come before this representative yet.")).toBeNull();
    });

    test("shows error with retry when detail request fails for an executive", () => {
        const refresh = jest.fn();
        mockLegislators([{ ...LEG_FULL, terms: [{ ...sampleExecutiveTerm, active: true }] }]);
        mockUseLegislator.mockReturnValue({ data: null, loading: false, error: new Error("network"), refresh });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-error")).toBeTruthy();
        expect(screen.getByText("Couldn't load the voting record.")).toBeTruthy();
        fireEvent.press(screen.getByTestId("botm-record-retry"));
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("renders the voting record for a career switcher with mixed legislative and executive terms", () => {
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }, sampleTerm2021],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-row-101")).toBeTruthy();
    });

    test("renders the voting record for a former executive officeholder with ended stamp", () => {
        mockLegislators([{ ...LEG_FULL, active: false, terms: [sampleExecutiveTerm] }]);
        mockLegislatorDetail({
            ...LEG_FULL,
            active: false,
            terms: [sampleExecutiveTerm],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-detail-ended-stamp")).toBeTruthy();
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-row-101")).toBeTruthy();
    });

    test("renders the voting record for an executive with multiple executive terms", () => {
        const priorExecutiveTerm: ILegislatorTermEntry = {
            ...sampleExecutiveTerm,
            id: 104,
            session_label: "2016–2020 Mayoral Term",
            term_start_year: 2016,
            term_end_year: 2020,
            began_on: "2016-12-08",
            ended_on: "2020-12-08",
            active: false,
        };
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }, priorExecutiveTerm],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-row-101")).toBeTruthy();
    });

    test("shows signed-in visitor vote and alignment badges for an executive", () => {
        mockUseBootstrap.mockReturnValue({ bootstrap: { ...BASE_BOOTSTRAP, current_user: { id: 1 } }, loading: false });
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("botm-user-vote-101")).toHaveTextContent("For");
        expect(screen.getByTestId("botm-alignment-101")).toHaveTextContent("Agreed");
        expect(screen.getByTestId("botm-alignment-102")).toHaveTextContent("Disagreed");
        expect(screen.getByTestId("botm-user-vote-103")).toHaveTextContent("Not voted");
        expect(screen.queryByTestId("botm-alignment-103")).toBeNull();
    });

    test("hides visitor vote and alignment badges for an executive when signed out", () => {
        mockUseBootstrap.mockReturnValue({ bootstrap: { ...BASE_BOOTSTRAP, current_user: null }, loading: false });
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getAllByTestId(/^botm-legislator-vote-/)).toHaveLength(4);
        expect(screen.queryAllByTestId(/^botm-user-vote-/)).toHaveLength(0);
        expect(screen.queryAllByTestId(/^botm-alignment-/)).toHaveLength(0);
    });

    test("preserves the voting record visibility across all tab selections for an executive", () => {
        mockLegislators([{ ...LEG_FULL, terms: [{ ...sampleExecutiveTerm, active: true }] }]);
        mockLegislatorDetail({
            ...LEG_FULL,
            terms: [{ ...sampleExecutiveTerm, active: true }],
            bill_of_the_month_votes: BOTM_VOTES,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);

        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();

        fireEvent.press(screen.getByRole("tab", { name: "Lifetime" }));
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();

        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        expect(screen.getByTestId("legislator-botm-record")).toBeTruthy();
    });

    test("hides the visitor's vote and alignment when signed out", () => {
        mockUseBootstrap.mockReturnValue({ bootstrap: { ...BASE_BOOTSTRAP, current_user: null }, loading: false });
        mockLegislatorDetail({ ...LEG_FULL, terms: [sampleTerm2025], bill_of_the_month_votes: BOTM_VOTES });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getAllByTestId(/^botm-legislator-vote-/)).toHaveLength(4);
        expect(screen.queryAllByTestId(/^botm-user-vote-/)).toHaveLength(0);
        expect(screen.queryAllByTestId(/^botm-alignment-/)).toHaveLength(0);
    });

    test("keeps rendering the cached list legislator while the detail request loads or fails", () => {
        mockLegislatorDetail(null, false, new Error("network"));
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("Carol Legislator")).toBeTruthy();
        expect(screen.getByTestId("legislator-detail-charts")).toBeTruthy();
    });

    test("shows a skeleton, not the empty message, while the detail request loads", () => {
        mockLegislatorDetail(null, true);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("Bill of the Month Voting Record")).toBeTruthy();
        expect(screen.getByTestId("botm-record-skeleton")).toBeTruthy();
        expect(screen.queryByText("No Bills of the Month have come before this representative yet.")).toBeNull();
    });

    test("shows an error with a retry, not the empty message, when the detail request fails", () => {
        const refresh = jest.fn();
        mockUseLegislator.mockReturnValue({ data: null, loading: false, error: new Error("network"), refresh });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("Couldn't load the voting record.")).toBeTruthy();
        expect(screen.queryByText("No Bills of the Month have come before this representative yet.")).toBeNull();
        fireEvent.press(screen.getByTestId("botm-record-retry"));
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    test("wires useFocusedSync with 15s polling and triggers both refresh and refreshDetail", () => {
        (useFocusedSync as jest.Mock).mockClear();
        const refreshList = jest.fn();
        const refreshDetail = jest.fn();
        mockUseLegislators.mockReturnValue({
            data: [LEG_FULL],
            loading: false,
            error: null,
            refresh: refreshList,
            isOnline: true,
        });
        mockUseLegislator.mockReturnValue({
            data: { ...LEG_FULL, terms: [sampleTerm2025], bill_of_the_month_votes: BOTM_VOTES },
            loading: false,
            error: null,
            refresh: refreshDetail,
        });

        render(<LegislatorDetailScreen route={makeRoute(99)} />);

        expect(useFocusedSync).toHaveBeenCalledWith({
            refresh: expect.any(Function),
            pollMs: 15000,
        });
        const syncArg = (useFocusedSync as jest.Mock).mock.calls[0][0] as { refresh: () => void };
        syncArg.refresh();
        expect(refreshList).toHaveBeenCalledTimes(1);
        expect(refreshDetail).toHaveBeenCalledTimes(1);
    });

    test("refreshes legislator list and detail when screen regains focus after navigating to BillDetail", () => {
        const refreshList = jest.fn();
        const refreshDetail = jest.fn();
        const navigate = jest.fn();
        mockUseLegislators.mockReturnValue({
            data: [LEG_FULL],
            loading: false,
            error: null,
            refresh: refreshList,
            isOnline: true,
        });
        mockUseLegislator.mockReturnValue({
            data: { ...LEG_FULL, terms: [sampleTerm2025], bill_of_the_month_votes: BOTM_VOTES },
            loading: false,
            error: null,
            refresh: refreshDetail,
        });

        const { rerender } = render(<LegislatorDetailScreen route={makeRoute(99)} navigation={{ navigate }} />);
        expect(refreshList).not.toHaveBeenCalled();
        expect(refreshDetail).not.toHaveBeenCalled();

        fireEvent.press(screen.getByLabelText("CB26-0001: Clean Water Act"));
        expect(navigate).toHaveBeenCalledWith("BillDetail", { id: 101 });

        rerender(<LegislatorDetailScreen route={makeRoute(99)} navigation={{ navigate }} />);
        expect(refreshList).toHaveBeenCalledTimes(1);
        expect(refreshDetail).toHaveBeenCalledTimes(1);
    });

    test("renders loading skeleton instead of not-found when list is empty and detail is still loading", () => {
        mockLegislators([], false);
        mockLegislatorDetail(null, true);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-detail-skeleton")).toBeTruthy();
        expect(screen.queryByTestId("legislator-detail-not-found")).toBeNull();
    });

    test("renders error with retry instead of not-found when list is empty and detail fails", () => {
        const refreshList = jest.fn();
        const refreshDetail = jest.fn();
        mockUseLegislators.mockReturnValue({
            data: [],
            loading: false,
            error: null,
            refresh: refreshList,
            isOnline: true,
        });
        mockUseLegislator.mockReturnValue({
            data: null,
            loading: false,
            error: new Error("Failed to fetch legislator"),
            refresh: refreshDetail,
        });
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("Failed to fetch legislator")).toBeTruthy();
        expect(screen.queryByTestId("legislator-detail-not-found")).toBeNull();
        fireEvent.press(screen.getByTestId("legislator-not-found-retry"));
        expect(refreshList).toHaveBeenCalledTimes(1);
        expect(refreshDetail).toHaveBeenCalledTimes(1);
    });
});

describe("formatReleaseMonth", () => {
    afterEach(() => {
        jest.restoreAllMocks();
    });

    test("reads a release date in UTC even west of London", () => {
        const format = Intl.DateTimeFormat;
        jest.spyOn(Date.prototype, "toLocaleDateString").mockImplementation(function (
            this: Date,
            locales?: Intl.LocalesArgument,
            options?: Intl.DateTimeFormatOptions,
        ) {
            return format(locales, { timeZone: "America/Los_Angeles", ...options }).format(this);
        });
        expect(formatReleaseMonth("2026-10-01")).toBe("Oct 2026");
    });
});

describe("LegislatorDetailScreen (Phase 35 PARITY-09 mobile-canonical)", () => {
    beforeEach(() => {
        mockUseBootstrap.mockReset();
        mockUseLegislators.mockReset();
        mockUseLegislator.mockReset();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
        mockLegislatorDetail(null);
    });

    test("renders header with legislator full_name (testID=legislator-detail-header)", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-detail-header")).toBeTruthy();
        expect(screen.getByText("Carol Legislator")).toBeTruthy();
    });

    test("renders score tiles (testID=legislator-detail-score-tiles) when score present", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-detail-score-tiles")).toBeTruthy();
    });

    test("renders charts panel (testID=legislator-detail-charts) always expanded", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-detail-charts")).toBeTruthy();
    });

    test("renders email contact row when legislator has email", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("carol@example.gov")).toBeTruthy();
    });

    test("renders phone contact row when legislator has phone", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByText("410-555-1234")).toBeTruthy();
    });

    test("renders empty state when no legislator with matching id found", () => {
        mockLegislators([{ ...LEG_FULL, id: 1 }]);
        render(<LegislatorDetailScreen route={makeRoute(999)} />);
        expect(screen.queryByTestId("legislator-detail-header")).toBeNull();
    });

    test("snapshot: detail screen renders key testIDs for full legislator record", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByTestId("legislator-detail-header")).toBeTruthy();
        expect(screen.getByTestId("legislator-detail-score-tiles")).toBeTruthy();
        expect(screen.getByTestId("legislator-detail-charts")).toBeTruthy();
    });

    test("renders 3-segment control tabs for Current Term, Lifetime, and Term History", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        expect(screen.getByRole("tab", { name: "Current Term" })).toBeTruthy();
        expect(screen.getByRole("tab", { name: "Lifetime" })).toBeTruthy();
        expect(screen.getByRole("tab", { name: "Term History" })).toBeTruthy();
    });

    test("renders terms ordered descending by term_start_year in Term History", () => {
        const legWithTerms = {
            ...LEG_FULL,
            terms: [sampleTerm2021, sampleTerm2025],
        };
        mockLegislators([legWithTerms]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        const termCards = screen.getAllByTestId("legislator-term-card");
        expect(termCards.length).toBe(2);
        expect(termCards[0]).toHaveTextContent(/119th Congress/);
        expect(termCards[1]).toHaveTextContent(/117th Congress/);
    });

    test("renders empty state when legislator has empty terms array", () => {
        const legNoTerms = {
            ...LEG_FULL,
            terms: [],
        };
        mockLegislators([legNoTerms]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        expect(screen.getByTestId("legislator-history-empty")).toBeTruthy();
        expect(screen.queryAllByTestId("legislator-term-card").length).toBe(0);
    });

    test("distinguishes active term from past ended terms with status badges", () => {
        const legWithTerms = {
            ...LEG_FULL,
            terms: [sampleTerm2025, sampleTerm2021],
        };
        mockLegislators([legWithTerms]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        const activeBadge = screen.getByTestId("term-active-badge");
        const pastBadge = screen.getByTestId("term-past-badge");
        expect(activeBadge).toHaveTextContent("Current Term");
        expect(pastBadge).toHaveTextContent("Ended");
    });

    test("renders district and locale aggregate score tiles from percentages, with no counts", () => {
        const legWithTerms = {
            ...LEG_FULL,
            terms: [sampleTerm2025],
        };
        mockLegislators([legWithTerms]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        const districtTile = screen.getByTestId("term-district-score-tile");
        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(districtTile).toHaveTextContent(/80%/);
        expect(districtTile).toHaveTextContent(/73% Agreed/);
        expect(districtTile).toHaveTextContent(/18% Disagreed/);
        expect(districtTile).toHaveTextContent(/MD3 Agreement/);
        expect(localeTile).toHaveTextContent(/75%/);
        expect(localeTile).toHaveTextContent(/69% Agreed/);
        expect(localeTile).toHaveTextContent(/23% Disagreed/);
        expect(localeTile).toHaveTextContent(/Locale Agreement/);
    });

    // @lat: [[voter-privacy-threshold#The mobile legislator screens draw percentages or the placeholder]]
    test("says 'Not enough votes yet' on a suppressed tile and on a cached score with no flag", () => {
        const zeroScoreTerm = {
            ...sampleTerm2025,
            district_score: {
                count_agreed: 6,
                count_disagreed: 3,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
                comparison_suppressed: true,
                agreed_percent: null,
                disagreed_percent: null,
                no_legislator_vote_percent: null,
                legislator_abstained_percent: null,
            },
            locale_score: {
                count_agreed: 4321,
                count_disagreed: 1234,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
        };
        mockLegislators([{ ...LEG_FULL, terms: [zeroScoreTerm] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent(/Not enough votes yet/);
        expect(districtTile).not.toHaveTextContent(/NaN|%|6 Agreed/);
        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent(/Not enough votes yet/);
        expect(localeTile).not.toHaveTextContent(/4321|1234|%/);
    });

    test("renders personal agreement score tile when authenticated user voted in term", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: { ...BASE_BOOTSTRAP, current_user: { id: 42 } },
            loading: false,
        });
        mockLegislators([{ ...LEG_FULL, terms: [sampleTerm2025] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent(/80%/);
        expect(userTile).toHaveTextContent(/4 Agreed/);
        expect(userTile).toHaveTextContent(/1 Disagreed/);
        expect(userTile).toHaveTextContent(/Your Agreement/);
    });

    test("renders unvoted term notice when authenticated user has no votes in term", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: { ...BASE_BOOTSTRAP, current_user: { id: 42 } },
            loading: false,
        });
        mockLegislators([{ ...LEG_FULL, terms: [sampleTerm2021] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        expect(screen.getByTestId("unvoted-term-notice")).toBeTruthy();
        expect(screen.getByText("No Personal Votes Recorded")).toBeTruthy();
        expect(screen.queryByTestId("term-user-score-tile")).toBeNull();
    });

    test("renders unauthenticated visitor prompt when user is not logged in", () => {
        mockUseBootstrap.mockReturnValue({
            bootstrap: { ...BASE_BOOTSTRAP, current_user: null },
            loading: false,
        });
        mockLegislators([{ ...LEG_FULL, terms: [sampleTerm2025] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        expect(screen.getByTestId("unauthenticated-history-notice")).toBeTruthy();
        expect(screen.getByText("Compare Your Votes")).toBeTruthy();
        expect(screen.queryByTestId("term-user-score-tile")).toBeNull();
        expect(screen.getByTestId("term-district-score-tile")).toBeTruthy();
    });

    test("renders agreement score tiles and chart toggle on executive office terms alongside executive stamp", () => {
        const executiveTermWithScores: ILegislatorTermEntry = {
            ...sampleExecutiveTerm,
            district_score: sampleDistrictScore,
            locale_score: sampleLocaleScore,
            user_score: sampleUserScore,
        };
        mockUseBootstrap.mockReturnValue({
            bootstrap: { ...BASE_BOOTSTRAP, current_user: { id: 42 } },
            loading: false,
        });
        mockLegislators([{ ...LEG_FULL, terms: [executiveTermWithScores] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

        expect(screen.getByTestId("term-card-executive-stamp")).toBeTruthy();
        expect(screen.getByText("Executive Office")).toBeTruthy();
        expect(screen.queryByTestId("executive-office-notice")).toBeNull();
        expect(screen.queryByText("Executive Office — Roll-Call Votes Not Applicable")).toBeNull();

        expect(screen.getByTestId("term-user-score-tile")).toBeTruthy();
        expect(screen.getByTestId("term-district-score-tile")).toBeTruthy();
        expect(screen.getByTestId("term-locale-score-tile")).toBeTruthy();
        expect(screen.getByTestId("term-charts-toggle-103")).toBeTruthy();
    });

    test("renders Record Corrected badge when term has correction explanation", () => {
        mockLegislators([{ ...LEG_FULL, terms: [sampleTerm2021] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        expect(screen.getByTestId("record-corrected-badge")).toBeTruthy();
        expect(screen.getByText("Record Corrected")).toBeTruthy();
    });

    test("opens historical repair modal and displays audit tracing on badge press", () => {
        mockLegislators([{ ...LEG_FULL, terms: [sampleTerm2021] }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
        fireEvent.press(screen.getByTestId("record-corrected-badge"));
        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toBeTruthy();
        expect(screen.getByText("Official Term Date Correction")).toBeTruthy();
        expect(screen.getByText("Delta: +2")).toBeTruthy();
        expect(screen.getByText(/Audit Provenance:/)).toBeTruthy();
        expect(screen.getByText(/Score Reference: term_202/)).toBeTruthy();
        fireEvent.press(screen.getByTestId("btn-repair-modal-close"));
    });

    test("coerces string route.params.id from deep links to match numeric legislator ID", () => {
        mockLegislators([LEG_FULL]);
        render(<LegislatorDetailScreen route={{ params: { id: "99" } }} />);
        expect(mockUseLegislator).toHaveBeenCalledWith(99);
        expect(screen.getByTestId("legislator-detail-header")).toBeTruthy();
        expect(screen.getByText("Carol Legislator")).toBeTruthy();
    });

    test.each(["javascript:alert(1)", "sway://organizations/1/memberships/5"])(
        "does not render or open unsafe legislator.link scheme: %s",
        (unsafeLink) => {
            const openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
            mockLegislators([{ ...LEG_FULL, link: unsafeLink }]);
            render(<LegislatorDetailScreen route={makeRoute(99)} />);
            expect(screen.queryByTestId("legislator-detail-link")).toBeNull();
            expect(openURLSpy).not.toHaveBeenCalled();
            openURLSpy.mockRestore();
        },
    );

    test("renders and opens https:// legislator.link via Linking.openURL", () => {
        const openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        mockLegislators([{ ...LEG_FULL, link: "https://example.gov/carol" }]);
        render(<LegislatorDetailScreen route={makeRoute(99)} />);
        const linkRow = screen.getByTestId("legislator-detail-link");
        expect(linkRow).toBeTruthy();
        fireEvent.press(linkRow);
        expect(openURLSpy).toHaveBeenCalledWith("https://example.gov/carol");
        openURLSpy.mockRestore();
    });
});
