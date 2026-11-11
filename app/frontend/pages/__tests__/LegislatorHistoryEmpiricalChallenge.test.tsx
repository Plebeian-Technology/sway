// @lat: [[current-legislator-term#Which term a legislator is serving now#Which term a payload describes]]
// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import type { IHistoricalScoreExplanation, ILegislatorTermEntry } from "app/frontend/types/legislators";

const usePollMock = vi.fn<(interval: number, options: { only: string[] }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>();
const routerPostMock = vi.fn<() => void>();
const routerPutMock = vi.fn<() => void>();
const routerGetMock = vi.fn<() => void>();
const routerReloadMock = vi.fn<() => void>();

vi.mock("@inertiajs/react", () => ({
    usePoll: (interval: number, options: { only: string[] }) => {
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
        get: () => routerGetMock(),
        reload: () => routerReloadMock(),
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

import Legislator from "app/frontend/pages/Legislator";

afterEach(() => {
    cleanup();
    currentUserMock = { id: 1 };
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
    routerPostMock.mockClear();
    routerPutMock.mockClear();
    routerGetMock.mockClear();
    routerReloadMock.mockClear();
    window.history.replaceState({}, "", "/legislators/42");
});

const baseLegislator = {
    id: 42,
    full_name: "John Empirical",
    external_id: "ext-42",
    title: "Senator",
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

describe("CHALLENGE 1: Descending Term Ordering & Boundary Stress", () => {
    it("strictly orders 5 scrambled terms by term_start_year descending", () => {
        const terms: ILegislatorTermEntry[] = [
            {
                id: 1,
                session_label: "2015 Term",
                term_start_year: 2015,
                term_end_year: 2017,
                began_on: "2015-01-01",
                ended_on: "2017-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 5,
                session_label: "2025 Term",
                term_start_year: 2025,
                term_end_year: 2027,
                began_on: "2025-01-01",
                ended_on: null,
                district_name: "D1",
                is_executive: false,
                active: true,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 3,
                session_label: "2019 Term",
                term_start_year: 2019,
                term_end_year: 2021,
                began_on: "2019-01-01",
                ended_on: "2021-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 4,
                session_label: "2023 Term",
                term_start_year: 2023,
                term_end_year: 2025,
                began_on: "2023-01-01",
                ended_on: "2025-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 2,
                session_label: "2017 Term",
                term_start_year: 2017,
                term_end_year: 2019,
                began_on: "2017-01-01",
                ended_on: "2019-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
        ];

        render(<Legislator legislator={{ ...baseLegislator, terms }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const cards = screen.getAllByTestId("legislator-term-card");
        expect(cards).toHaveLength(5);
        expect(cards[0]).toHaveTextContent("2025 Term");
        expect(cards[1]).toHaveTextContent("2023 Term");
        expect(cards[2]).toHaveTextContent("2019 Term");
        expect(cards[3]).toHaveTextContent("2017 Term");
        expect(cards[4]).toHaveTextContent("2015 Term");
    });

    it("handles undefined and null terms gracefully with empty state", () => {
        const { unmount } = render(<Legislator legislator={{ ...baseLegislator, terms: undefined }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        expect(screen.getByTestId("legislator-history-empty")).toBeInTheDocument();
        unmount();

        render(<Legislator legislator={{ ...baseLegislator, terms: null as unknown as undefined }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        expect(screen.getByTestId("legislator-history-empty")).toBeInTheDocument();
    });
});

describe("CHALLENGE 2: Active vs Past Badges Semantics", () => {
    it("ensures mutually exclusive active and past badges across multiple terms", () => {
        const terms: ILegislatorTermEntry[] = [
            {
                id: 201,
                session_label: "Current Active Session",
                term_start_year: 2025,
                term_end_year: 2027,
                began_on: "2025-01-01",
                ended_on: null,
                district_name: "D1",
                is_executive: false,
                active: true,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 202,
                session_label: "Ended Past Session 1",
                term_start_year: 2023,
                term_end_year: 2025,
                began_on: "2023-01-01",
                ended_on: "2025-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 203,
                session_label: "Ended Past Session 2",
                term_start_year: 2021,
                term_end_year: 2023,
                began_on: "2021-01-01",
                ended_on: "2023-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
        ];

        render(<Legislator legislator={{ ...baseLegislator, terms }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const cards = screen.getAllByTestId("legislator-term-card");
        expect(cards).toHaveLength(3);

        expect(cards[0].querySelector("[data-testid='term-active-badge']")).toBeInTheDocument();
        expect(cards[0].querySelector("[data-testid='term-past-badge']")).not.toBeInTheDocument();

        expect(cards[1].querySelector("[data-testid='term-active-badge']")).not.toBeInTheDocument();
        expect(cards[1].querySelector("[data-testid='term-past-badge']")).toBeInTheDocument();

        expect(cards[2].querySelector("[data-testid='term-active-badge']")).not.toBeInTheDocument();
        expect(cards[2].querySelector("[data-testid='term-past-badge']")).toBeInTheDocument();
    });

    it("former legislator with no active terms displays Ended badges for all terms", () => {
        const terms: ILegislatorTermEntry[] = [
            {
                id: 301,
                session_label: "Session 2019",
                term_start_year: 2019,
                term_end_year: 2021,
                began_on: "2019-01-01",
                ended_on: "2021-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
            {
                id: 302,
                session_label: "Session 2017",
                term_start_year: 2017,
                term_end_year: 2019,
                began_on: "2017-01-01",
                ended_on: "2019-01-01",
                district_name: "D1",
                is_executive: false,
                active: false,
                district_score: null,
                locale_score: null,
                user_score: null,
                correction_explanation: null,
            },
        ];

        render(<Legislator legislator={{ ...baseLegislator, active: false, terms }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.queryByTestId("term-active-badge")).not.toBeInTheDocument();
        expect(screen.getAllByTestId("term-past-badge")).toHaveLength(2);
    });
});

describe("CHALLENGE 3: Agreement Percentage & Division-by-Zero Arithmetic Oracles", () => {
    it("handles 100% agreement oracle (agreed > 0, disagreed == 0)", () => {
        const term: ILegislatorTermEntry = {
            id: 401,
            session_label: "100% Agreement Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD7",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 50,
                count_disagreed: 0,
                count_no_legislator_vote: 5,
                count_legislator_abstained: 2,
            },
            locale_score: {
                count_agreed: 100,
                count_disagreed: 0,
                count_no_legislator_vote: 10,
                count_legislator_abstained: 0,
            },
            user_score: {
                count_agreed: 12,
                count_disagreed: 0,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("100%");
        expect(districtTile).toHaveTextContent("50 Agreed");
        expect(districtTile).toHaveTextContent("0 Disagreed");
        expect(districtTile).toHaveTextContent("5 No Vote");

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("100%");
        expect(localeTile).toHaveTextContent("100 Agreed");
        expect(localeTile).toHaveTextContent("0 Disagreed");

        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("100%");
        expect(userTile).toHaveTextContent("12 Agreed");
        expect(userTile).toHaveTextContent("0 Disagreed");
    });

    it("handles 0% agreement oracle (agreed == 0, disagreed > 0)", () => {
        const term: ILegislatorTermEntry = {
            id: 402,
            session_label: "0% Agreement Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD7",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 0,
                count_disagreed: 25,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 0,
                count_disagreed: 50,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: {
                count_agreed: 0,
                count_disagreed: 8,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("0%");
        expect(districtTile).toHaveTextContent("0 Agreed");
        expect(districtTile).toHaveTextContent("25 Disagreed");

        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("0%");
        expect(userTile).toHaveTextContent("0 Agreed");
        expect(userTile).toHaveTextContent("8 Disagreed");
    });

    it("handles rounding oracle: 2/3 rounds to 67%, 1/3 rounds to 33%", () => {
        const term: ILegislatorTermEntry = {
            id: 403,
            session_label: "Rounding Check Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD7",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 2,
                count_disagreed: 1,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 1,
                count_disagreed: 2,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("67%");

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("33%");
    });

    it("handles division by zero when agreed == 0 and disagreed == 0 (with non-zero abstentions/no-votes)", () => {
        const term: ILegislatorTermEntry = {
            id: 404,
            session_label: "Abstain Only Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD7",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 14,
                count_legislator_abstained: 3,
            },
            locale_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 20,
                count_legislator_abstained: 5,
            },
            user_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 2,
                count_legislator_abstained: 1,
            },
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("No votes recorded (--%)");
        expect(districtTile).not.toHaveTextContent("NaN");
        expect(districtTile).toHaveTextContent("14 No Vote");

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("No votes recorded (--%)");
        expect(localeTile).not.toHaveTextContent("NaN");
        expect(localeTile).toHaveTextContent("20 No Vote");

        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("--%");
        expect(userTile).not.toHaveTextContent("NaN");
        expect(userTile).toHaveTextContent("2 No Vote");
        expect(userTile).toHaveTextContent("1 Abstained");
    });

    it("handles large values without integer overflow or display glitches", () => {
        const term: ILegislatorTermEntry = {
            id: 405,
            session_label: "Big Numbers Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD7",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 1000000,
                count_disagreed: 500000,
                count_no_legislator_vote: 10000,
                count_legislator_abstained: 5000,
            },
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("67%");
        expect(districtTile).toHaveTextContent("1000000 Agreed");
        expect(districtTile).toHaveTextContent("500000 Disagreed");
    });
});

describe("CHALLENGE 4: Executive Office & Missing Coverage Enforcements", () => {
    it("executive office renders score tiles, charts, and executive stamp when score objects exist", () => {
        const executiveTermWithScores: ILegislatorTermEntry = {
            id: 501,
            session_label: "Mayor 2020–2024",
            term_start_year: 2020,
            term_end_year: 2024,
            began_on: "2020-12-08",
            ended_on: "2024-12-10",
            district_name: "Citywide",
            is_executive: true,
            active: false,
            district_score: {
                count_agreed: 99,
                count_disagreed: 1,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 99,
                count_disagreed: 1,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: {
                count_agreed: 99,
                count_disagreed: 1,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [executiveTermWithScores] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.getByTestId("term-card-executive-stamp")).toHaveTextContent("Executive Office");
        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();
        expect(screen.getByTestId("term-district-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-locale-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-user-score-tile")).toBeInTheDocument();

        const toggleBtn = screen.getByTestId("term-charts-toggle-501");
        expect(toggleBtn).toHaveTextContent("Show term charts");
        expect(screen.queryByTestId("term-charts-panel-501")).not.toBeInTheDocument();

        fireEvent.click(toggleBtn);
        expect(toggleBtn).toHaveTextContent("Hide term charts");
        expect(screen.getByTestId("term-charts-panel-501")).toBeInTheDocument();
        expect(screen.getByTestId("voter-agreement-chart")).toBeInTheDocument();
        expect(screen.getAllByTestId("voter-district-agreement-chart")).toHaveLength(2);

        fireEvent.click(toggleBtn);
        expect(toggleBtn).toHaveTextContent("Show term charts");
        expect(screen.queryByTestId("term-charts-panel-501")).not.toBeInTheDocument();
    });

    it("does not render executive stamp for legislative terms", () => {
        const legislativeTerm: ILegislatorTermEntry = {
            id: 509,
            session_label: "Session 2021–2023",
            term_start_year: 2021,
            term_end_year: 2023,
            began_on: "2021-01-01",
            ended_on: "2023-01-01",
            district_name: "MD1",
            is_executive: false,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [legislativeTerm] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.queryByTestId("term-card-executive-stamp")).not.toBeInTheDocument();
    });

    it("executive term with zero total recorded votes displays fallback text (--%)", () => {
        const zeroVotesExecutiveTerm: ILegislatorTermEntry = {
            id: 510,
            session_label: "Mayor 2020–2024",
            term_start_year: 2020,
            term_end_year: 2024,
            began_on: "2020-12-08",
            ended_on: "2024-12-10",
            district_name: "Citywide",
            is_executive: true,
            active: false,
            district_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [zeroVotesExecutiveTerm] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("No votes recorded (--%)");
        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("No votes recorded (--%)");
    });

    it("authenticated user with unvoted term displays clear explanatory notice without misleading 0%", () => {
        const unvotedTerm: ILegislatorTermEntry = {
            id: 502,
            session_label: "Session 2017–2019",
            term_start_year: 2017,
            term_end_year: 2019,
            began_on: "2017-01-01",
            ended_on: "2019-01-01",
            district_name: "MD1",
            is_executive: false,
            active: false,
            district_score: {
                count_agreed: 20,
                count_disagreed: 5,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 40,
                count_disagreed: 10,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [unvotedTerm] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const notice = screen.getByTestId("unvoted-term-notice");
        expect(notice).toHaveTextContent("No Personal Votes Recorded");
        expect(notice).not.toHaveTextContent("0%");
        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();

        expect(screen.getByTestId("term-district-score-tile")).toHaveTextContent("80%");
        expect(screen.getByTestId("term-locale-score-tile")).toHaveTextContent("80%");
    });

    it("unauthenticated visitor sees sign-in prompt and community scores but never personal score tile", () => {
        currentUserMock = null;
        const term: ILegislatorTermEntry = {
            id: 503,
            session_label: "Session 2021–2023",
            term_start_year: 2021,
            term_end_year: 2023,
            began_on: "2021-01-01",
            ended_on: "2023-01-01",
            district_name: "MD1",
            is_executive: false,
            active: false,
            district_score: {
                count_agreed: 15,
                count_disagreed: 5,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 30,
                count_disagreed: 10,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const unauthNotice = screen.getByTestId("unauthenticated-history-notice");
        expect(unauthNotice).toHaveTextContent("Compare Your Votes");
        const loginLink = screen.getByRole("link", { name: /sign in/i });
        expect(loginLink).toHaveAttribute("href", "/login");
        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();
        expect(screen.queryByTestId("unvoted-term-notice")).not.toBeInTheDocument();
    });

    it("executive office for unauthenticated visitor renders community scores and sign-in prompt but suppresses personal user score", () => {
        currentUserMock = null;
        const executiveTerm: ILegislatorTermEntry = {
            id: 504,
            session_label: "Mayor 2020–2024",
            term_start_year: 2020,
            term_end_year: 2024,
            began_on: "2020-12-08",
            ended_on: "2024-12-10",
            district_name: null,
            is_executive: true,
            active: false,
            district_score: {
                count_agreed: 70,
                count_disagreed: 30,
                count_no_legislator_vote: 5,
                count_legislator_abstained: 0,
            },
            locale_score: {
                count_agreed: 80,
                count_disagreed: 20,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [executiveTerm] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.getByTestId("term-card-executive-stamp")).toHaveTextContent("Executive Office");
        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();
        expect(screen.getByTestId("unauthenticated-history-notice")).toHaveTextContent("Compare Your Votes");
        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();
        expect(screen.queryByTestId("unvoted-term-notice")).not.toBeInTheDocument();

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("70%");
        expect(districtTile).toHaveTextContent("70 Agreed");
        expect(districtTile).toHaveTextContent("30 Disagreed");
        expect(districtTile).toHaveTextContent("5 No Vote");

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("80%");

        const toggle = screen.getByTestId("term-charts-toggle-504");
        fireEvent.click(toggle);

        const panel = screen.getByTestId("term-charts-panel-504");
        expect(panel).toBeInTheDocument();
        expect(screen.queryByText(/Your agreement/i)).not.toBeInTheDocument();
    });

    it("executive office handles entirely null scores gracefully without rendering charts toggle", () => {
        const executiveTermNullScores: ILegislatorTermEntry = {
            id: 505,
            session_label: "Governor 2018–2022",
            term_start_year: 2018,
            term_end_year: 2022,
            began_on: "2018-01-10",
            ended_on: "2022-01-12",
            district_name: null,
            is_executive: true,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [executiveTermNullScores] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.getByTestId("term-card-executive-stamp")).toBeInTheDocument();
        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();
        expect(screen.getByTestId("unvoted-term-notice")).toBeInTheDocument();
        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("No votes recorded (--%)");
        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("No votes recorded (--%)");

        expect(screen.queryByTestId("term-charts-toggle-505")).not.toBeInTheDocument();
    });

    it("handles rogue/malformed string and zero-vote scores on executive terms safely", () => {
        const rogueExecutiveTerm: ILegislatorTermEntry = {
            id: 506,
            session_label: "Mayor 2012–2016",
            term_start_year: 2012,
            term_end_year: 2016,
            began_on: "2012-12-04",
            ended_on: "2016-12-06",
            district_name: null,
            is_executive: true,
            active: false,
            district_score: {
                count_agreed: "25" as unknown as number,
                count_disagreed: "25" as unknown as number,
                count_no_legislator_vote: "0" as unknown as number,
                count_legislator_abstained: "0" as unknown as number,
            },
            locale_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 8,
                count_legislator_abstained: 2,
            },
            user_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [rogueExecutiveTerm] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("50%");
        expect(districtTile).toHaveTextContent("25 Agreed");
        expect(districtTile).toHaveTextContent("25 Disagreed");
        expect(districtTile).not.toHaveTextContent("NaN");

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("No votes recorded (--%)");
        expect(localeTile).toHaveTextContent("8 No Vote");
        expect(localeTile).not.toHaveTextContent("NaN");

        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("--%");
        expect(userTile).not.toHaveTextContent("NaN");
    });

    it("renders career switcher terms accurately distinguishing executive and legislative offices", () => {
        const activeExecutiveTerm: ILegislatorTermEntry = {
            id: 507,
            session_label: "Mayor 2024–2028",
            term_start_year: 2024,
            term_end_year: 2028,
            began_on: "2024-12-10",
            ended_on: null,
            district_name: null,
            is_executive: true,
            active: true,
            district_score: {
                count_agreed: 18,
                count_disagreed: 2,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        const priorLegislativeTerm: ILegislatorTermEntry = {
            id: 508,
            session_label: "City Council 2020–2024",
            term_start_year: 2020,
            term_end_year: 2024,
            began_on: "2020-12-08",
            ended_on: "2024-12-10",
            district_name: "District 7",
            is_executive: false,
            active: false,
            district_score: {
                count_agreed: 40,
                count_disagreed: 10,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [activeExecutiveTerm, priorLegislativeTerm],
                }}
            />,
        );
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const cards = screen.getAllByTestId("legislator-term-card");
        expect(cards).toHaveLength(2);

        expect(cards[0]).toHaveTextContent("Mayor 2024–2028");
        expect(cards[0]).toHaveTextContent("At-Large · 2024–2028");
        expect(cards[0]).toHaveTextContent("Current Term");
        expect(cards[0]).toHaveTextContent("Executive Office");
        expect(cards[0]).not.toHaveTextContent("Ended");

        expect(cards[1]).toHaveTextContent("City Council 2020–2024");
        expect(cards[1]).toHaveTextContent("District 7 · 2020–2024");
        expect(cards[1]).toHaveTextContent("Ended");
        expect(cards[1]).not.toHaveTextContent("Executive Office");
        expect(cards[1]).not.toHaveTextContent("Current Term");

        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();
    });
});

describe("CHALLENGE 5: Historical Score Repair Modal & Negative/Zero Deltas", () => {
    it("handles negative delta in repair explanation (-4 votes)", () => {
        const negativeRepair: IHistoricalScoreExplanation = {
            title: "Overcounted Roll Call Correction",
            body: "Audit removed 4 duplicate roll calls.",
            delta: -4,
            score_type: "term_601",
        };

        const term: ILegislatorTermEntry = {
            id: 601,
            session_label: "Session 2021",
            term_start_year: 2021,
            term_end_year: 2023,
            began_on: "2021-01-01",
            ended_on: "2023-01-01",
            district_name: "MD1",
            is_executive: false,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: negativeRepair,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        fireEvent.click(screen.getByTestId("record-corrected-badge"));
        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toHaveTextContent("Delta: -4");
        expect(modal).toHaveTextContent("Overcounted Roll Call Correction");
        expect(modal).toHaveTextContent("term_601");
    });

    it("handles zero or null delta in repair explanation without displaying empty Delta badge", () => {
        const zeroDeltaRepair: IHistoricalScoreExplanation = {
            title: "Official Seat Boundary Reclassification",
            body: "District boundaries updated; no score change.",
            delta: 0,
            score_type: "term_602",
        };

        const term: ILegislatorTermEntry = {
            id: 602,
            session_label: "Session 2019",
            term_start_year: 2019,
            term_end_year: 2021,
            began_on: "2019-01-01",
            ended_on: "2021-01-01",
            district_name: "MD1",
            is_executive: false,
            active: false,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: zeroDeltaRepair,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        fireEvent.click(screen.getByTestId("record-corrected-badge"));
        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).not.toHaveTextContent("Delta:");
        expect(modal).toHaveTextContent("Official Seat Boundary Reclassification");
    });
});

describe("CHALLENGE 6: Interactive Collapsible Term Charts & Deep Linking", () => {
    it("toggles collapsible term charts open and closed on user demand", () => {
        const term: ILegislatorTermEntry = {
            id: 701,
            session_label: "Interactive Charts Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD1",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 10,
                count_disagreed: 2,
                count_no_legislator_vote: 1,
                count_legislator_abstained: 0,
            },
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const toggleBtn = screen.getByTestId("term-charts-toggle-701");
        expect(toggleBtn).toHaveTextContent("Show term charts");
        expect(screen.queryByTestId("term-charts-panel-701")).not.toBeInTheDocument();

        fireEvent.click(toggleBtn);
        expect(toggleBtn).toHaveTextContent("Hide term charts");
        expect(screen.getByTestId("term-charts-panel-701")).toBeInTheDocument();

        fireEvent.click(toggleBtn);
        expect(toggleBtn).toHaveTextContent("Show term charts");
        expect(screen.queryByTestId("term-charts-panel-701")).not.toBeInTheDocument();
    });

    it("deep links to history tab when legislators_tab=history is present in URL", () => {
        window.history.replaceState({}, "", "/legislators/42?legislators_tab=history");

        const term: ILegislatorTermEntry = {
            id: 702,
            session_label: "Deep Linked Session",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD1",
            is_executive: false,
            active: true,
            district_score: null,
            locale_score: null,
            user_score: null,
            correction_explanation: null,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);

        expect(screen.getByTestId("legislator-history-terms-list")).toBeInTheDocument();
        expect(screen.getByText("Deep Linked Session")).toBeInTheDocument();
    });
});

describe("CHALLENGE 7: Read-Only Invariant Enforcement", () => {
    it("never triggers router.post, router.put, router.get or router.reload across all history interactions", () => {
        const repair: IHistoricalScoreExplanation = {
            title: "Audit Correction",
            body: "Audit notes.",
            delta: 1,
            score_type: "term_801",
        };

        const term: ILegislatorTermEntry = {
            id: 801,
            session_label: "Read Only Term",
            term_start_year: 2025,
            term_end_year: 2027,
            began_on: "2025-01-01",
            ended_on: null,
            district_name: "MD1",
            is_executive: false,
            active: true,
            district_score: {
                count_agreed: 10,
                count_disagreed: 2,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
            locale_score: null,
            user_score: null,
            correction_explanation: repair,
        };

        render(<Legislator legislator={{ ...baseLegislator, terms: [term] }} />);

        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        fireEvent.click(screen.getByTestId("term-charts-toggle-801"));
        fireEvent.click(screen.getByTestId("record-corrected-badge"));
        fireEvent.click(screen.getByRole("button", { name: /close/i }));
        fireEvent.click(screen.getByTestId("term-charts-toggle-801"));
        fireEvent.click(screen.getByRole("tab", { name: "Current term" }));
        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(routerPostMock).not.toHaveBeenCalled();
        expect(routerPutMock).not.toHaveBeenCalled();
        expect(routerGetMock).not.toHaveBeenCalled();
        expect(routerReloadMock).not.toHaveBeenCalled();
    });
});
