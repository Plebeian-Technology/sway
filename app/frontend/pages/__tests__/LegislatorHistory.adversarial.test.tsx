// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
// @lat: [[legislator-history-serialization#Why unvoted terms are rendered with distinct coverage indicators]]
// @lat: [[legislator-history-serialization#Why historical score corrections are embedded directly in term payloads]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import type { ILegislatorTermEntry } from "app/frontend/types/legislators";

const usePollMock = vi.fn<(interval: number, options: { only: string[] }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>(() => false);
const routerPostMock = vi.fn<() => void>();
const routerPutMock = vi.fn<() => void>();
const routerDeleteMock = vi.fn<() => void>();
const routerVisitMock = vi.fn<() => void>();

vi.mock("@inertiajs/react", () => ({
    usePoll: function usePoll(interval: number, options: { only: string[] }) {
        usePollMock(interval, options);
    },
    Link: ({ href, children, ...props }: { href: string; children: ReactNode }) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
    router: {
        post: () => routerPostMock(),
        put: () => routerPutMock(),
        delete: () => routerDeleteMock(),
        visit: () => routerVisitMock(),
        get: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
    },
}));

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({
    useScoreSubscription: (only: string[]) => scoreSubscriptionMock(only),
}));

let currentUserMock: { id: number; email?: string } | null = { id: 1 };
vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => currentUserMock,
}));

vi.mock("app/frontend/components/legislators/charts/LegislatorChartsPanel", () => ({
    default: () => <div data-testid="charts-panel-stub" />,
}));

vi.mock("app/frontend/components/legislators/charts/VoterAgreementChart", () => ({
    default: ({ title }: { title: string }) => <div data-testid="mock-voter-agreement-chart">{title}</div>,
}));

vi.mock("app/frontend/components/legislators/charts/VoterDistrictAgreementChart", () => ({
    default: ({ title }: { title: string }) => <div data-testid="mock-district-agreement-chart">{title}</div>,
}));

import Legislator from "app/frontend/pages/Legislator";
import { groupScore } from "app/frontend/__tests__/support/groupScore";

afterEach(() => {
    cleanup();
    currentUserMock = { id: 1 };
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
    routerPostMock.mockClear();
    routerPutMock.mockClear();
    routerDeleteMock.mockClear();
    routerVisitMock.mockClear();
    window.history.replaceState({}, "", "/legislators/42");
});

const baseLegislator = {
    id: 42,
    full_name: "Jane Doe",
    external_id: "abc-123",
    title: "Delegate",
    party: "D",
    photo_url: "",
    email: null,
    phone: null,
    twitter: null,
    link: null,
    district: null,
    user_legislator_score: null,
    lifetime_score: null,
} as unknown as sway.ILegislator;

const sampleDistrictScore: sway.scoring.IAgreeable = {
    count_agreed: 8,
    count_disagreed: 2,
    count_no_legislator_vote: 1,
    count_legislator_abstained: 0,
};

const sampleLocaleScore: sway.scoring.IAgreeable = {
    count_agreed: 18,
    count_disagreed: 6,
    count_no_legislator_vote: 2,
    count_legislator_abstained: 0,
};

const sampleUserScore: sway.scoring.IAgreeable = {
    count_agreed: 4,
    count_disagreed: 1,
    count_no_legislator_vote: 0,
    count_legislator_abstained: 0,
};

describe("Adversarial Scenario 1: Executive Office Term Agreement Scoring & Stamp Preservation", () => {
    it("renders roll-call tiles and charts when executive term contains non-null score data while keeping executive stamp", () => {
        const executiveTermWithScores: ILegislatorTermEntry = {
            id: 201,
            session_label: "2020–2024 Mayoral Administration",
            term_start_year: 2020,
            term_end_year: 2024,
            began_on: "2020-12-08",
            ended_on: "2024-12-10",
            district_name: null,
            is_executive: true,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: {
                count_agreed: 10,
                count_disagreed: 0,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            correction_explanation: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [executiveTermWithScores],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.getByTestId("term-card-executive-stamp")).toBeInTheDocument();
        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();

        expect(screen.getByTestId("term-district-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-locale-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-user-score-tile")).toBeInTheDocument();
        expect(screen.queryByTestId("unvoted-term-notice")).not.toBeInTheDocument();
        expect(screen.queryByTestId("unauthenticated-history-notice")).not.toBeInTheDocument();
        expect(screen.getByTestId("term-charts-toggle-201")).toBeInTheDocument();

        expect(screen.getByText("100%")).toBeInTheDocument();
        expect(screen.getByText("80%")).toBeInTheDocument();
    });

    it("falls back to 'At-Large' when district_name is null on executive term", () => {
        const executiveTerm: ILegislatorTermEntry = {
            id: 202,
            session_label: "2023–2027 Gubernatorial Term",
            term_start_year: 2023,
            term_end_year: 2027,
            began_on: "2023-01-18",
            ended_on: null,
            district_name: null,
            is_executive: true,
            active: true,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [executiveTerm],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const card = screen.getByTestId("legislator-term-card");
        expect(card).toHaveTextContent(/At-Large · 2023–2027/);
        expect(card).not.toHaveTextContent("null");
        expect(card).not.toHaveTextContent("undefined");
        expect(screen.getByTestId("term-active-badge")).toBeInTheDocument();
        expect(screen.getByTestId("term-card-executive-stamp")).toBeInTheDocument();
    });

    it("displays Record Corrected badge and opens repair modal on an executive term alongside term score tiles", () => {
        const executiveTermWithAudit: ILegislatorTermEntry = {
            id: 203,
            session_label: "2016–2020 Mayoral Term",
            term_start_year: 2016,
            term_end_year: 2020,
            began_on: "2016-12-06",
            ended_on: "2020-12-08",
            district_name: null,
            is_executive: true,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: {
                title: "Executive Inauguration Date Adjustment",
                body: "Corrected official inauguration certification date from municipal archives.",
                delta: null,
                score_type: "term_dates_203",
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [executiveTermWithAudit],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const correctedBadge = screen.getByTestId("record-corrected-badge");
        expect(correctedBadge).toBeInTheDocument();

        fireEvent.click(correctedBadge);

        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toBeInTheDocument();
        expect(modal).toHaveTextContent("Executive Inauguration Date Adjustment");
        expect(modal).toHaveTextContent("term_dates_203");
        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();
        expect(screen.getByTestId("term-district-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("unvoted-term-notice")).toBeInTheDocument();
    });
});

describe("Adversarial Scenario 2: Unvoted Term vs Genuine 0% Agreement vs Zero-Vote Objects", () => {
    it("distinguishes genuine 0% agreement from an unvoted term", () => {
        const termGenuineZeroAgreement: ILegislatorTermEntry = {
            id: 301,
            session_label: "118th Congress",
            term_start_year: 2023,
            term_end_year: 2025,
            began_on: "2023-01-03",
            ended_on: "2025-01-03",
            district_name: "MD7",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: {
                count_agreed: 0,
                count_disagreed: 8,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            correction_explanation: null,
        };

        const termUnvoted: ILegislatorTermEntry = {
            id: 302,
            session_label: "117th Congress",
            term_start_year: 2021,
            term_end_year: 2023,
            began_on: "2021-01-03",
            ended_on: "2023-01-03",
            district_name: "MD7",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [termGenuineZeroAgreement, termUnvoted],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const cards = screen.getAllByTestId("legislator-term-card");
        expect(cards).toHaveLength(2);

        expect(cards[0]).toHaveTextContent("118th Congress");
        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("0%");
        expect(userTile).toHaveTextContent("0 Agreed");
        expect(userTile).toHaveTextContent("8 Disagreed");
        expect(cards[0]).not.toHaveTextContent("No Personal Votes Recorded");

        expect(cards[1]).toHaveTextContent("117th Congress");
        const unvotedNotice = screen.getByTestId("unvoted-term-notice");
        expect(unvotedNotice).toHaveTextContent(/No Personal Votes Recorded/i);
        expect(unvotedNotice).not.toHaveTextContent("0%");
    });

    it("handles zero-total-vote user_score object safely with '--%' display without NaN or division by zero", () => {
        const zeroVoteUserTerm: ILegislatorTermEntry = {
            id: 303,
            session_label: "116th Congress",
            term_start_year: 2019,
            term_end_year: 2021,
            began_on: "2019-01-03",
            ended_on: "2021-01-03",
            district_name: "MD7",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 4,
                count_legislator_abstained: 2,
            },
            correction_explanation: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [zeroVoteUserTerm],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("--%");
        expect(userTile).not.toHaveTextContent("NaN");
        expect(userTile).toHaveTextContent("0 Agreed");
        expect(userTile).toHaveTextContent("0 Disagreed");
        expect(userTile).toHaveTextContent("4 No Vote");
        expect(userTile).toHaveTextContent("2 Abstained");
    });

    it("renders community agreement charts while skipping user chart when user is unvoted", () => {
        const unvotedTerm: ILegislatorTermEntry = {
            id: 304,
            session_label: "117th Congress",
            term_start_year: 2021,
            term_end_year: 2023,
            began_on: "2021-01-03",
            ended_on: "2023-01-03",
            district_name: "MD3",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [unvotedTerm],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const toggleBtn = screen.getByTestId("term-charts-toggle-304");
        expect(toggleBtn).toBeInTheDocument();
        expect(toggleBtn).toHaveTextContent("Show term charts");

        fireEvent.click(toggleBtn);

        expect(toggleBtn).toHaveTextContent("Hide term charts");
        const chartsPanel = screen.getByTestId("term-charts-panel-304");
        expect(chartsPanel).toBeInTheDocument();

        expect(screen.queryByTestId("mock-voter-agreement-chart")).not.toBeInTheDocument();
        const districtCharts = screen.getAllByTestId("mock-district-agreement-chart");
        expect(districtCharts).toHaveLength(2);
        expect(districtCharts[0]).toHaveTextContent("MD3 agreement · 117th Congress");
        expect(districtCharts[1]).toHaveTextContent("Locale agreement · 117th Congress");
    });
});

describe("Adversarial Scenario 3: Unauthenticated Visitor Flow & Public Transparency", () => {
    it("renders visitor sign-in prompt with /login link and preserves full public community scores and audit badges", () => {
        currentUserMock = null;

        const termWithAudit: ILegislatorTermEntry = {
            id: 401,
            session_label: "119th Congress",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-03",
            ended_on: null,
            district_name: "MD1",
            is_executive: false,
            active: true,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: {
                title: "Roll-Call Audit Correction",
                body: "Chamber vote totals adjusted after legislative clerk published errata.",
                delta: 3,
                score_type: "district_term_401",
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [termWithAudit],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const notice = screen.getByTestId("unauthenticated-history-notice");
        expect(notice).toHaveTextContent(/Compare Your Votes/i);
        expect(notice).toHaveTextContent(/Sign in or register with your address/i);
        const loginLink = screen.getByRole("link", { name: "Sign in" });
        expect(loginLink).toHaveAttribute("href", "/login");

        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();
        expect(screen.queryByTestId("unvoted-term-notice")).not.toBeInTheDocument();

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("80%");
        expect(districtTile).toHaveTextContent("73% Agreed");
        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("75%");
        expect(localeTile).toHaveTextContent("69% Agreed");

        const auditBadge = screen.getByTestId("record-corrected-badge");
        expect(auditBadge).toBeInTheDocument();
        fireEvent.click(auditBadge);

        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toBeInTheDocument();
        expect(modal).toHaveTextContent("Roll-Call Audit Correction");
        expect(modal).toHaveTextContent("Delta: +3");
    });
});

describe("Adversarial Scenario 4: Repair Modal Data Integrity & Boundary Stress", () => {
    it("handles negative deltas correctly with leading minus sign", () => {
        const negativeDeltaTerm: ILegislatorTermEntry = {
            id: 501,
            session_label: "115th Congress",
            term_start_year: 2017,
            term_end_year: 2019,
            began_on: "2017-01-03",
            ended_on: "2019-01-03",
            district_name: "MD3",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: {
                title: "Overcounted Vote Disallowance",
                body: "Removed duplicate proxy vote improperly attributed to district score.",
                delta: -4,
                score_type: "term_501",
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [negativeDeltaTerm],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        fireEvent.click(screen.getByTestId("record-corrected-badge"));

        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toHaveTextContent("Delta: -4");
        expect(modal).toHaveTextContent("Overcounted Vote Disallowance");
        expect(modal).toHaveTextContent("Score Reference: term_501");
    });

    it("suppresses delta badge when delta is zero or null without layout failure", () => {
        const zeroDeltaTerm: ILegislatorTermEntry = {
            id: 502,
            session_label: "114th Congress",
            term_start_year: 2015,
            term_end_year: 2017,
            began_on: "2015-01-03",
            ended_on: "2017-01-03",
            district_name: "MD3",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: {
                title: "Typographical Metadata Correction",
                body: "Corrected bill title metadata with zero change to final vote count.",
                delta: 0,
                score_type: "term_502",
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [zeroDeltaTerm],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        fireEvent.click(screen.getByTestId("record-corrected-badge"));

        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toHaveTextContent("Typographical Metadata Correction");
        expect(modal).not.toHaveTextContent("Delta:");
    });

    it("maintains isolated state across multiple term repair modals", () => {
        const termA: ILegislatorTermEntry = {
            id: 503,
            session_label: "Term Alpha",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-03",
            ended_on: null,
            district_name: "MD1",
            is_executive: false,
            active: true,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: {
                title: "Audit Title Alpha",
                body: "Body Alpha",
                delta: 1,
                score_type: "type_alpha",
            },
        };

        const termB: ILegislatorTermEntry = {
            id: 504,
            session_label: "Term Beta",
            term_start_year: 2021,
            term_end_year: 2023,
            began_on: "2021-01-03",
            ended_on: "2023-01-03",
            district_name: "MD1",
            is_executive: false,
            active: false,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: null,
            correction_explanation: {
                title: "Audit Title Beta",
                body: "Body Beta",
                delta: 2,
                score_type: "type_beta",
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [termA, termB],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const badges = screen.getAllByTestId("record-corrected-badge");
        expect(badges).toHaveLength(2);

        fireEvent.click(badges[0]);
        let modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toHaveTextContent("Audit Title Alpha");
        expect(modal).not.toHaveTextContent("Audit Title Beta");

        fireEvent.click(screen.getByRole("button", { name: /close/i }));
        expect(screen.queryByTestId("historical-repair-modal")).not.toBeInTheDocument();

        fireEvent.click(badges[1]);
        modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toHaveTextContent("Audit Title Beta");
        expect(modal).not.toHaveTextContent("Audit Title Alpha");
    });
});

describe("Adversarial Scenario 5: Zero-Mutation Invariant & URL Deep Linking", () => {
    it("respects ?legislators_tab=history deep link URL and issues ZERO router mutations", () => {
        window.history.replaceState({}, "", "/legislators/42?legislators_tab=history");

        const term: ILegislatorTermEntry = {
            id: 601,
            session_label: "119th Congress",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-03",
            ended_on: null,
            district_name: "MD3",
            is_executive: false,
            active: true,
            district_score: groupScore(sampleDistrictScore),
            locale_score: groupScore(sampleLocaleScore),
            user_score: sampleUserScore,
            correction_explanation: {
                title: "Deep Link Audit",
                body: "Audit verification",
                delta: 1,
                score_type: "test",
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [term],
                }}
            />,
        );

        expect(screen.getByTestId("legislator-history-terms-list")).toBeInTheDocument();
        expect(screen.getByText("119th Congress")).toBeInTheDocument();

        fireEvent.click(screen.getByRole("tab", { name: "Lifetime" }));
        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        fireEvent.click(screen.getByTestId("term-charts-toggle-601"));
        fireEvent.click(screen.getByTestId("record-corrected-badge"));
        fireEvent.click(screen.getByRole("button", { name: /close/i }));

        expect(routerPostMock).not.toHaveBeenCalled();
        expect(routerPutMock).not.toHaveBeenCalled();
        expect(routerDeleteMock).not.toHaveBeenCalled();
        expect(routerVisitMock).not.toHaveBeenCalled();
    });

    it("resiliently sorts wildly out-of-order terms without crashing or mutating input", () => {
        const term2015: ILegislatorTermEntry = {
            id: 701,
            session_label: "2015 Session",
            term_start_year: 2015,
            term_end_year: 2017,
            began_on: "2015-01-03",
            ended_on: "2017-01-03",
            district_name: "MD3",
            is_executive: false,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        const term2025: ILegislatorTermEntry = {
            id: 702,
            session_label: "2025 Session",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-03",
            ended_on: null,
            district_name: "MD3",
            is_executive: false,
            active: true,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        const term2019: ILegislatorTermEntry = {
            id: 703,
            session_label: "2019 Session",
            term_start_year: 2019,
            term_end_year: 2021,
            began_on: "2019-01-03",
            ended_on: "2021-01-03",
            district_name: "MD3",
            is_executive: false,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        const inputList = [term2015, term2025, term2019];

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: inputList,
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const cards = screen.getAllByTestId("legislator-term-card");
        expect(cards).toHaveLength(3);
        expect(cards[0]).toHaveTextContent("2025 Session");
        expect(cards[1]).toHaveTextContent("2019 Session");
        expect(cards[2]).toHaveTextContent("2015 Session");

        expect(inputList[0].term_start_year).toBe(2015);
        expect(inputList[1].term_start_year).toBe(2025);
        expect(inputList[2].term_start_year).toBe(2019);
    });
});
