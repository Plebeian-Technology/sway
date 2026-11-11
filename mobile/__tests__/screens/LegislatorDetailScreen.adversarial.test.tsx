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

const mockApiClient = {
    get: jest.fn(async (..._args: unknown[]) => ({})),
    post: jest.fn(async (..._args: unknown[]) => ({})),
    patch: jest.fn(async (..._args: unknown[]) => ({})),
    delete: jest.fn(async (..._args: unknown[]) => undefined),
};

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiClient.get(...args),
        post: (...args: unknown[]) => mockApiClient.post(...args),
        patch: (...args: unknown[]) => mockApiClient.patch(...args),
        delete: (...args: unknown[]) => mockApiClient.delete(...args),
    },
}));

jest.mock("../../src/components/LegislatorChartsPanel", () => {
    return {
        LegislatorChartsPanel: ({ testID }: { testID?: string; score?: unknown }) => {
            const { View } = require("react-native");
            return require("react").createElement(View, { testID: testID ?? "legislator-charts-panel" });
        },
        default: ({ testID }: { testID?: string; score?: unknown }) => {
            const { View } = require("react-native");
            return require("react").createElement(View, { testID: testID ?? "legislator-charts-panel" });
        },
    };
});

jest.mock("../../src/components/SkeletonCard", () => {
    return {
        SkeletonCard: ({ testID }: { testID?: string }) => {
            const { View } = require("react-native");
            return require("react").createElement(View, { testID: testID ?? "skeleton-card" });
        },
        default: ({ testID }: { testID?: string }) => {
            const { View } = require("react-native");
            return require("react").createElement(View, { testID: testID ?? "skeleton-card" });
        },
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
import { fireEvent, render, screen } from "@testing-library/react-native";
import LegislatorDetailScreen from "../../src/screens/LegislatorDetailScreen";
import { HistoricalRepairModal } from "../../src/components/legislators/HistoricalRepairModal";
import { calculateAgreement } from "../../src/types/legislator";
import type { ILegislatorTermEntry, IHistoricalScoreExplanation } from "../../src/types/legislator";

const BASE_BOOTSTRAP = {
    locale: { id: 1, name: "baltimore-maryland-united_states" },
    sway_locales: [{ id: 1, name: "baltimore-maryland-united_states" }],
    current_user: { id: 1 },
};

const BASE_SCORE = {
    count_agreed: 10,
    count_disagreed: 5,
    count_no_legislator_vote: 1,
    count_legislator_abstained: 0,
};

const LEG_FULL = {
    id: 42,
    full_name: "Senator Adversary",
    title: "Senator",
    party: "Independent",
    email: "adversary@example.gov",
    phone: "410-555-9999",
    photo_url: null,
    user_legislator_score: BASE_SCORE,
    lifetime_score: BASE_SCORE,
    active: true,
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

describe("LegislatorDetailScreen Adversarial Stress Tests (Historical Legislator Agreement by Term)", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockUseBootstrap.mockReturnValue({ bootstrap: BASE_BOOTSTRAP, loading: false });
        mockUseLegislator.mockReturnValue({ data: null, loading: false, error: null, refresh: jest.fn() });
    });

    describe("ADVERSARIAL 1: Executive Office Term Agreement Scoring Invariant", () => {
        test("renders agreement tiles, percentages, and expandable charts for executive terms with scores while keeping executive stamp", () => {
            const executiveTermWithScores: ILegislatorTermEntry = {
                id: 999,
                session_label: "Executive Mayoral Term 2020-2024",
                term_start_year: 2020,
                term_end_year: 2024,
                began_on: "2020-12-08",
                ended_on: "2024-12-10",
                district_name: null,
                is_executive: true,
                active: false,
                district_score: { count_agreed: 50, count_disagreed: 10 },
                locale_score: { count_agreed: 100, count_disagreed: 20 },
                user_score: { count_agreed: 15, count_disagreed: 5 },
                correction_explanation: null,
            };

            mockLegislators([{ ...LEG_FULL, terms: [executiveTermWithScores] }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

            expect(screen.getByTestId("term-card-executive-stamp")).toBeTruthy();
            expect(screen.getByText("Executive Office")).toBeTruthy();
            expect(screen.queryByTestId("executive-office-notice")).toBeNull();
            expect(screen.queryByText("Executive Office — Roll-Call Votes Not Applicable")).toBeNull();

            expect(screen.getByTestId("term-user-score-tile")).toBeTruthy();
            expect(screen.getByTestId("term-district-score-tile")).toBeTruthy();
            expect(screen.getByTestId("term-locale-score-tile")).toBeTruthy();
            expect(screen.queryByTestId("unvoted-term-notice")).toBeNull();
            expect(screen.queryByTestId("unauthenticated-history-notice")).toBeNull();

            const toggle = screen.getByTestId("term-charts-toggle-999");
            expect(toggle).toBeTruthy();
            fireEvent.press(toggle);

            expect(screen.getByTestId("term-charts-panel-999")).toBeTruthy();
            expect(screen.getByTestId("term-chart-user-999")).toBeTruthy();
            expect(screen.getByTestId("term-chart-district-999")).toBeTruthy();
            expect(screen.getByTestId("term-chart-locale-999")).toBeTruthy();
        });

        test("renders unvoted notice and community score tiles when executive term has null user_score", () => {
            const executiveTermNullUserScore: ILegislatorTermEntry = {
                id: 998,
                session_label: "Governor Term 2018–2022",
                term_start_year: 2018,
                term_end_year: 2022,
                began_on: "2018-01-10",
                ended_on: "2022-01-12",
                district_name: null,
                is_executive: true,
                active: false,
                district_score: { count_agreed: 40, count_disagreed: 10 },
                locale_score: { count_agreed: 80, count_disagreed: 20 },
                user_score: null,
                correction_explanation: null,
            };

            mockLegislators([{ ...LEG_FULL, terms: [executiveTermNullUserScore] }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

            expect(screen.getByTestId("term-card-executive-stamp")).toBeTruthy();
            expect(screen.queryByTestId("executive-office-notice")).toBeNull();
            expect(screen.getByTestId("unvoted-term-notice")).toBeTruthy();
            expect(screen.getByText("No Personal Votes Recorded")).toBeTruthy();
            expect(screen.queryByTestId("term-user-score-tile")).toBeNull();
            expect(screen.getByTestId("term-district-score-tile")).toBeTruthy();
            expect(screen.getByTestId("term-locale-score-tile")).toBeTruthy();
        });
    });

    describe("ADVERSARIAL 2: Unvoted Term vs Unauthenticated Visitor Flow Invariants", () => {
        test("authenticated user with null user_score renders unvoted notice and retains community scores", () => {
            mockUseBootstrap.mockReturnValue({
                bootstrap: { ...BASE_BOOTSTRAP, current_user: { id: 77 } },
                loading: false,
            });

            const unvotedTerm: ILegislatorTermEntry = {
                id: 501,
                session_label: "116th Congress",
                term_start_year: 2019,
                term_end_year: 2021,
                began_on: "2019-01-03",
                ended_on: "2021-01-03",
                district_name: "District 7",
                is_executive: false,
                active: false,
                district_score: { count_agreed: 12, count_disagreed: 3 },
                locale_score: { count_agreed: 30, count_disagreed: 10 },
                user_score: null,
                correction_explanation: null,
            };

            mockLegislators([{ ...LEG_FULL, terms: [unvotedTerm] }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

            expect(screen.getByTestId("unvoted-term-notice")).toBeTruthy();
            expect(screen.getByText("No Personal Votes Recorded")).toBeTruthy();
            expect(screen.queryByTestId("term-user-score-tile")).toBeNull();
            expect(screen.queryByTestId("unauthenticated-history-notice")).toBeNull();

            expect(screen.getByTestId("term-district-score-tile")).toBeTruthy();
            expect(screen.getByTestId("term-locale-score-tile")).toBeTruthy();
        });

        test("unauthenticated visitor renders compare prompt with sign-in button and retains community scores", () => {
            mockUseBootstrap.mockReturnValue({
                bootstrap: { ...BASE_BOOTSTRAP, current_user: null },
                loading: false,
            });

            const term: ILegislatorTermEntry = {
                id: 502,
                session_label: "118th Congress",
                term_start_year: 2023,
                term_end_year: 2025,
                began_on: "2023-01-03",
                ended_on: "2025-01-03",
                district_name: "District 2",
                is_executive: false,
                active: true,
                district_score: { count_agreed: 20, count_disagreed: 5 },
                locale_score: { count_agreed: 50, count_disagreed: 15 },
                user_score: null,
                correction_explanation: null,
            };

            mockLegislators([{ ...LEG_FULL, terms: [term] }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

            expect(screen.getByTestId("unauthenticated-history-notice")).toBeTruthy();
            expect(screen.getByText("Compare Your Votes")).toBeTruthy();
            expect(screen.getByText("Sign in")).toBeTruthy();

            expect(screen.queryByTestId("term-user-score-tile")).toBeNull();
            expect(screen.queryByTestId("unvoted-term-notice")).toBeNull();

            expect(screen.getByTestId("term-district-score-tile")).toBeTruthy();
            expect(screen.getByTestId("term-locale-score-tile")).toBeTruthy();
        });
    });

    describe("ADVERSARIAL 3: Repair Modal Data Integrity & Boundary Stress", () => {
        test("handles negative delta (-5) with proper label formatting without crashing", () => {
            const negativeDeltaExplanation: IHistoricalScoreExplanation = {
                title: "Overcounted Vote Audit Deduction",
                body: "Audit discovered 5 duplicate committee roll-calls.",
                delta: -5,
                score_type: "term_historical_audit",
            };

            const onClose = jest.fn();
            render(
                <HistoricalRepairModal
                    explanation={negativeDeltaExplanation}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={true}
                    onClose={onClose}
                />,
            );

            expect(screen.getByTestId("historical-repair-modal")).toBeTruthy();
            expect(screen.getByText("Delta: -5")).toBeTruthy();
            expect(screen.getByText("Overcounted Vote Audit Deduction")).toBeTruthy();
            expect(screen.getByText("Score Reference: term_historical_audit")).toBeTruthy();

            fireEvent.press(screen.getByTestId("btn-repair-modal-close"));
            expect(onClose).toHaveBeenCalledTimes(1);
        });

        test("handles zero delta and null delta by omitting delta badge cleanly", () => {
            const zeroDeltaExplanation: IHistoricalScoreExplanation = {
                title: "Zero Delta Clarification",
                body: "Audit reclassified abstentions without modifying aggregate score.",
                delta: 0,
                score_type: "term_abstention_reclassification",
            };

            const { rerender } = render(
                <HistoricalRepairModal
                    explanation={zeroDeltaExplanation}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={true}
                    onClose={jest.fn()}
                />,
            );

            expect(screen.queryByText(/Delta:/)).toBeNull();

            const nullDeltaExplanation: IHistoricalScoreExplanation = {
                title: "Null Delta Boundary",
                body: "Textual record clarification with no score calculation impact.",
                delta: null,
                score_type: "term_record_note",
            };

            rerender(
                <HistoricalRepairModal
                    explanation={nullDeltaExplanation}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={true}
                    onClose={jest.fn()}
                />,
            );

            expect(screen.queryByText(/Delta:/)).toBeNull();
            expect(screen.getByText("Null Delta Boundary")).toBeTruthy();
        });

        test("returns null immediately when explanation is null or visible is false", () => {
            const { rerender } = render(
                <HistoricalRepairModal
                    explanation={null}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={true}
                    onClose={jest.fn()}
                />,
            );
            expect(screen.queryByTestId("historical-repair-modal")).toBeNull();

            rerender(
                <HistoricalRepairModal
                    explanation={{
                        title: "Hidden Modal",
                        body: "Should not appear",
                        delta: 1,
                        score_type: "test",
                    }}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={false}
                    onClose={jest.fn()}
                />,
            );
            const modal = screen.queryByTestId("historical-repair-modal");
            if (modal) {
                expect(modal.props.visible).toBe(false);
            } else {
                expect(modal).toBeNull();
            }
        });

        test("modal dismisses when pressing outer backdrop pressable", () => {
            const onClose = jest.fn();
            const explanation: IHistoricalScoreExplanation = {
                title: "Dismiss Test",
                body: "Dismiss verification.",
                delta: 3,
                score_type: "term_test",
            };

            render(
                <HistoricalRepairModal
                    explanation={explanation}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={true}
                    onClose={onClose}
                />,
            );

            const backdrop = screen.getByLabelText("Dismiss audit explanation");
            fireEvent.press(backdrop);
            expect(onClose).toHaveBeenCalledTimes(1);
        });
    });

    describe("ADVERSARIAL 4: Zero-Mutation Invariant & Local React State", () => {
        test("tab switching across all 3 tabs makes zero API client calls and zero mutations", () => {
            const terms: ILegislatorTermEntry[] = [
                {
                    id: 301,
                    session_label: "118th Congress",
                    term_start_year: 2023,
                    term_end_year: 2025,
                    began_on: "2023-01-03",
                    ended_on: "2025-01-03",
                    district_name: "District 1",
                    is_executive: false,
                    active: true,
                    district_score: { count_agreed: 10, count_disagreed: 2 },
                    locale_score: { count_agreed: 20, count_disagreed: 5 },
                    user_score: { count_agreed: 5, count_disagreed: 1 },
                    correction_explanation: null,
                },
            ];

            mockLegislators([{ ...LEG_FULL, terms }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            expect(mockApiClient.get).not.toHaveBeenCalled();
            expect(mockApiClient.post).not.toHaveBeenCalled();
            expect(mockApiClient.patch).not.toHaveBeenCalled();
            expect(mockApiClient.delete).not.toHaveBeenCalled();

            fireEvent.press(screen.getByRole("tab", { name: "Lifetime" }));
            expect(screen.getByTestId("legislator-detail-score-tiles-lifetime")).toBeTruthy();

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));
            expect(screen.getByTestId("legislator-history-terms-list")).toBeTruthy();

            const chartToggle = screen.getByTestId("term-charts-toggle-301");
            fireEvent.press(chartToggle);
            expect(screen.getByTestId("term-charts-panel-301")).toBeTruthy();
            fireEvent.press(chartToggle);
            expect(screen.queryByTestId("term-charts-panel-301")).toBeNull();

            fireEvent.press(screen.getByRole("tab", { name: "Current Term" }));
            expect(screen.getByTestId("legislator-detail-score-tiles")).toBeTruthy();

            expect(mockApiClient.get).not.toHaveBeenCalled();
            expect(mockApiClient.post).not.toHaveBeenCalled();
            expect(mockApiClient.patch).not.toHaveBeenCalled();
            expect(mockApiClient.delete).not.toHaveBeenCalled();
        });
    });

    describe("ADVERSARIAL 5: Safe Arithmetic Invariant (calculateAgreement)", () => {
        test("calculateAgreement handles string counts, undefined, null, and non-numeric garbage safely", () => {
            expect(calculateAgreement(null)).toEqual({
                displayPct: "--%",
                agreed: 0,
                disagreed: 0,
                noVote: 0,
                abstained: 0,
                total: 0,
            });
            expect(calculateAgreement(undefined)).toEqual({
                displayPct: "--%",
                agreed: 0,
                disagreed: 0,
                noVote: 0,
                abstained: 0,
                total: 0,
            });

            expect(calculateAgreement({ count_agreed: 0, count_disagreed: 0 })).toEqual({
                displayPct: "--%",
                agreed: 0,
                disagreed: 0,
                noVote: 0,
                abstained: 0,
                total: 0,
            });

            const stringScore = {
                count_agreed: "15",
                count_disagreed: "5",
                count_no_legislator_vote: "2",
                count_legislator_abstained: "1",
            };
            const result = calculateAgreement(stringScore);
            expect(result.displayPct).toBe("75%");
            expect(result.agreed).toBe(15);
            expect(result.disagreed).toBe(5);
            expect(result.noVote).toBe(2);
            expect(result.abstained).toBe(1);
            expect(result.total).toBe(20);

            expect(calculateAgreement({ count_agreed: 2, count_disagreed: 1 }).displayPct).toBe("67%");
            expect(calculateAgreement({ count_agreed: 10, count_disagreed: 0 }).displayPct).toBe("100%");
            expect(calculateAgreement({ count_agreed: 0, count_disagreed: 10 }).displayPct).toBe("0%");
        });
    });

    describe("ADVERSARIAL 6: Multi-Term Sorting Immutability & Independent State", () => {
        test("sorting terms descending by term_start_year does not mutate original terms array", () => {
            const originalTerms: ILegislatorTermEntry[] = [
                {
                    id: 1,
                    session_label: "Term 2015",
                    term_start_year: 2015,
                    term_end_year: 2017,
                    began_on: "2015-01-03",
                    ended_on: "2017-01-03",
                    district_name: "D1",
                    is_executive: false,
                    active: false,
                    district_score: null,
                    locale_score: null,
                    user_score: null,
                    correction_explanation: null,
                },
                {
                    id: 3,
                    session_label: "Term 2023",
                    term_start_year: 2023,
                    term_end_year: 2025,
                    began_on: "2023-01-03",
                    ended_on: "2025-01-03",
                    district_name: "D1",
                    is_executive: false,
                    active: true,
                    district_score: null,
                    locale_score: null,
                    user_score: null,
                    correction_explanation: null,
                },
                {
                    id: 2,
                    session_label: "Term 2019",
                    term_start_year: 2019,
                    term_end_year: 2021,
                    began_on: "2019-01-03",
                    ended_on: "2021-01-03",
                    district_name: "D1",
                    is_executive: false,
                    active: false,
                    district_score: null,
                    locale_score: null,
                    user_score: null,
                    correction_explanation: null,
                },
            ];

            const termsCopy = [...originalTerms];
            mockLegislators([{ ...LEG_FULL, terms: originalTerms }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

            const termCards = screen.getAllByTestId("legislator-term-card");
            expect(termCards.length).toBe(3);
            expect(termCards[0]).toHaveTextContent(/Term 2023/);
            expect(termCards[1]).toHaveTextContent(/Term 2019/);
            expect(termCards[2]).toHaveTextContent(/Term 2015/);

            expect(originalTerms[0].id).toBe(termsCopy[0].id);
            expect(originalTerms[1].id).toBe(termsCopy[1].id);
            expect(originalTerms[2].id).toBe(termsCopy[2].id);
        });

        test("expanding chart on one term card does not expand chart on other term cards", () => {
            const terms: ILegislatorTermEntry[] = [
                {
                    id: 701,
                    session_label: "Session 2023",
                    term_start_year: 2023,
                    term_end_year: 2025,
                    began_on: "2023-01-03",
                    ended_on: "2025-01-03",
                    district_name: "D1",
                    is_executive: false,
                    active: true,
                    district_score: { count_agreed: 5, count_disagreed: 1 },
                    locale_score: { count_agreed: 10, count_disagreed: 2 },
                    user_score: { count_agreed: 3, count_disagreed: 0 },
                    correction_explanation: null,
                },
                {
                    id: 702,
                    session_label: "Session 2021",
                    term_start_year: 2021,
                    term_end_year: 2023,
                    began_on: "2021-01-03",
                    ended_on: "2023-01-03",
                    district_name: "D1",
                    is_executive: false,
                    active: false,
                    district_score: { count_agreed: 8, count_disagreed: 2 },
                    locale_score: { count_agreed: 15, count_disagreed: 4 },
                    user_score: { count_agreed: 2, count_disagreed: 1 },
                    correction_explanation: null,
                },
            ];

            mockLegislators([{ ...LEG_FULL, terms }]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            fireEvent.press(screen.getByRole("tab", { name: "Term History" }));

            fireEvent.press(screen.getByTestId("term-charts-toggle-701"));
            expect(screen.getByTestId("term-charts-panel-701")).toBeTruthy();
            expect(screen.queryByTestId("term-charts-panel-702")).toBeNull();

            fireEvent.press(screen.getByTestId("term-charts-toggle-702"));
            expect(screen.getByTestId("term-charts-panel-701")).toBeTruthy();
            expect(screen.getByTestId("term-charts-panel-702")).toBeTruthy();
        });
    });

    describe("ADVERSARIAL 7: Former Representative Rendering & Tab Adaptation", () => {
        test("adapts tab label to year range and displays Ended badge when legislator active is false", () => {
            const formerLeg = {
                ...LEG_FULL,
                active: false,
                term_start_year: 2019,
                term_end_year: 2023,
                terms: [],
            };

            mockLegislators([formerLeg]);
            render(<LegislatorDetailScreen route={makeRoute(42)} />);

            expect(screen.getByTestId("legislator-detail-ended-stamp")).toBeTruthy();
            expect(screen.getByRole("tab", { name: "2019–2023" })).toBeTruthy();
            expect(screen.queryByRole("tab", { name: "Current Term" })).toBeNull();
        });
    });

    describe("ADVERSARIAL 8: Special Characters & Large Values in Repair Audit", () => {
        test("safely renders audit payload containing HTML entities, quotes, and large deltas", () => {
            const complexExplanation: IHistoricalScoreExplanation = {
                title: 'Correction <script>alert(1)</script> & "Audit #12"',
                body: "Body with 'single quotes', \n\nmultiple paragraphs, and unicode \u2014 \u2022 \u26A0.",
                delta: 99999,
                score_type: "term_ultra_audit_reference_id_with_extreme_length",
            };

            render(
                <HistoricalRepairModal
                    explanation={complexExplanation}
                    term={null}
                    legislatorName="Senator Adversary"
                    visible={true}
                    onClose={jest.fn()}
                />,
            );

            expect(screen.getByText('Correction <script>alert(1)</script> & "Audit #12"')).toBeTruthy();
            expect(screen.getByText("Delta: +99999")).toBeTruthy();
            expect(screen.getByText(/Body with 'single quotes'/)).toBeTruthy();
            expect(screen.getByText(/Score Reference: term_ultra_audit_reference_id_with_extreme_length/)).toBeTruthy();
        });
    });
});
