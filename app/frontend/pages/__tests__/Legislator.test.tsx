// @lat: [[current-legislator-term#Which term a legislator is serving now#Which term a payload describes]]

import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import type {
    IHistoricalScoreExplanation,
    ILegislatorBillOfTheMonthVote,
    ILegislatorTermEntry,
} from "app/frontend/types/legislators";

const usePollMock =
    vi.fn<(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) => void>();
const scoreSubscriptionMock = vi.fn<(only: string[]) => boolean>(() => false);
const routerPostMock = vi.fn<() => void>();
const routerPutMock = vi.fn<() => void>();

vi.mock("@inertiajs/react", () => ({
    usePoll: function usePoll(interval: number, options: { only: string[] }, pollOptions?: { background?: string }) {
        usePollMock(interval, options, pollOptions);
    },
    Link: ({
        href,
        children,
        prefetch: _prefetch,
        cacheFor: _cacheFor,
        viewTransition: _viewTransition,
        ...rest
    }: {
        href: string;
        children: ReactNode;
        prefetch?: unknown;
        cacheFor?: unknown;
        viewTransition?: unknown;
    }) => (
        <a href={href} {...rest}>
            {children}
        </a>
    ),
    router: {
        post: () => routerPostMock(),
        put: () => routerPutMock(),
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

import Legislator from "app/frontend/pages/Legislator";

afterEach(() => {
    cleanup();
    currentUserMock = { id: 1 };
    usePollMock.mockClear();
    scoreSubscriptionMock.mockClear();
    routerPostMock.mockClear();
    routerPutMock.mockClear();
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

const sampleActiveExecutiveTerm: ILegislatorTermEntry = {
    id: 104,
    session_label: "2024–2028 Mayoral Term",
    term_start_year: 2024,
    term_end_year: 2028,
    began_on: "2024-12-10",
    ended_on: null,
    district_name: null,
    is_executive: true,
    active: true,
    district_score: null,
    locale_score: null,
    user_score: null,
    correction_explanation: null,
};

describe("Legislator — poll + score-subscription refresh contract", () => {
    it("polls every 15s with only:[legislator] and subscribes on the same tuple", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    term_start_year: 2025,
                    term_end_year: 2027,
                }}
            />,
        );

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(15000, { only: ["legislator"] }, { background: "pause" });
        expect(scoreSubscriptionMock).toHaveBeenCalledWith(["legislator"]);
        expect(usePollMock.mock.calls[0][1].only).toBe(scoreSubscriptionMock.mock.calls[0][0]);
    });
});

describe("Legislator — locked tab copy", () => {
    it("active rep: tab 1 is 'Current term' with the year range as supporting text", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    term_start_year: 2025,
                    term_end_year: 2027,
                }}
            />,
        );

        expect(screen.getByRole("tab", { name: "Current term" })).toBeInTheDocument();
        expect(screen.getByText("2025–2027")).toBeInTheDocument();
        expect(screen.queryByTestId("legislator-detail-ended-stamp")).not.toBeInTheDocument();
    });

    it("former rep: tab 1 RELABELS to the term's year range and the Ended stamp renders", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: false,
                    term_start_year: 2019,
                    term_end_year: 2021,
                }}
            />,
        );

        expect(screen.getByRole("tab", { name: "2019–2021" })).toBeInTheDocument();
        expect(screen.queryByRole("tab", { name: "Current term" })).not.toBeInTheDocument();
        expect(screen.queryByText("Most recent term")).not.toBeInTheDocument();
        expect(screen.getByTestId("legislator-detail-ended-stamp")).toHaveTextContent("Ended");
    });

    // @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
    it("former rep: the tab shows the day they left, in place of the cycle's end year", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: false,
                    term_start_year: 2021,
                    term_end_year: 2027,
                    ended_on: "2026-07-11",
                }}
            />,
        );

        expect(screen.getByRole("tab", { name: "2021–Jul 11, 2026" })).toBeInTheDocument();
        expect(screen.queryByRole("tab", { name: "2021–2027" })).not.toBeInTheDocument();
    });

    it("active rep: the supporting text shows the day they arrived mid-cycle", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    term_start_year: 2025,
                    term_end_year: 2027,
                    began_on: "2025-03-04",
                }}
            />,
        );

        expect(screen.getByText("Mar 4, 2025–2027")).toBeInTheDocument();
    });

    it("former rep renders the frozen current-scope score tiles directly (no lifetime fallback)", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: false,
                    term_start_year: 2019,
                    term_end_year: 2021,
                    user_legislator_score: {
                        count_agreed: 7,
                        count_disagreed: 2,
                        count_no_legislator_vote: 1,
                        count_legislator_abstained: 0,
                    } as sway.scoring.IUserLegislatorScore,
                    lifetime_score: {
                        count_agreed: 99,
                        count_disagreed: 99,
                        count_no_legislator_vote: 99,
                        count_legislator_abstained: 0,
                    } as sway.scoring.IUserLegislatorScore,
                }}
            />,
        );

        expect(screen.getByText("7")).toBeInTheDocument();
        expect(screen.queryByText("99")).not.toBeInTheDocument();
    });
});

// @lat: [[legislators-tab-switching-design#Why districtLabel checks typeof === "number"]]
describe("Legislator — header subtitle district guard (WR-01, 65-REVIEW iteration 2)", () => {
    it("does not render the literal 'District undefined' when district lacks both a name and a number", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    term_start_year: 2025,
                    term_end_year: 2027,
                    district: {
                        id: 1,
                        name: null,
                        number: undefined,
                        region_code: "MD",
                    } as unknown as sway.IDistrict,
                }}
            />,
        );

        expect(screen.queryByText(/District undefined|\bnull\b/)).not.toBeInTheDocument();
    });

    it("renders the district number in the header subtitle when name is absent but number is present", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    term_start_year: 2025,
                    term_end_year: 2027,
                    district: {
                        id: 1,
                        name: null,
                        number: 40,
                        region_code: "MD",
                    } as unknown as sway.IDistrict,
                }}
            />,
        );

        expect(
            screen.getByText(
                (_, element) =>
                    element?.tagName.toLowerCase() === "p" && element.textContent === "Delegate · District 40",
            ),
        ).toBeInTheDocument();
    });
});

describe("Legislator — Historical Terms List Rendering & Order", () => {
    it("renders historical terms in descending order by term_start_year", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2021, sampleTerm2025],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const termCards = screen.getAllByTestId("legislator-term-card");
        expect(termCards).toHaveLength(2);

        expect(termCards[0]).toHaveTextContent("119th Congress");
        expect(termCards[0]).toHaveTextContent("2025–2027");
        expect(termCards[1]).toHaveTextContent("117th Congress");
        expect(termCards[1]).toHaveTextContent("2021–2023");
    });

    it("renders an empty state when legislator has no terms recorded", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.getByTestId("legislator-history-empty")).toHaveTextContent(/no historical terms/i);
        expect(screen.queryByTestId("legislator-term-card")).not.toBeInTheDocument();
    });
});

describe("Legislator — Term Active and Past Status Badges", () => {
    it("renders an Active badge for the currently running term and Past badge for previous terms", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2025, sampleTerm2021],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const activeBadges = screen.getAllByTestId("term-active-badge");
        const pastBadges = screen.getAllByTestId("term-past-badge");

        expect(activeBadges).toHaveLength(1);
        expect(activeBadges[0]).toHaveTextContent(/active|current/i);

        expect(pastBadges).toHaveLength(1);
        expect(pastBadges[0]).toHaveTextContent(/past|ended/i);
    });
});

describe("Legislator — District and Locale Aggregate Agreement Presentation", () => {
    it("renders district and locale aggregate percentage and count tiles", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2025],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("80%");
        expect(districtTile).toHaveTextContent("8 Agreed");
        expect(districtTile).toHaveTextContent("2 Disagreed");
        expect(districtTile).toHaveTextContent("MD3 Agreement");

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("75%");
        expect(localeTile).toHaveTextContent("18 Agreed");
        expect(localeTile).toHaveTextContent("6 Disagreed");
    });

    it("guards against division by zero when aggregate scores have 0 total votes", () => {
        const zeroVotesTerm: ILegislatorTermEntry = {
            ...sampleTerm2025,
            district_score: {
                count_agreed: 0,
                count_disagreed: 0,
                count_no_legislator_vote: 0,
                count_legislator_abstained: 0,
            },
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [zeroVotesTerm],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent(/no votes recorded|--%/i);
        expect(districtTile).not.toHaveTextContent("NaN");
    });
});

describe("Legislator — Authenticated User Score Presentation", () => {
    it("renders personal user score percentage and counts when user_score is present", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2025],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const userTile = screen.getByTestId("term-user-score-tile");
        expect(userTile).toHaveTextContent("80%");
        expect(userTile).toHaveTextContent("4 Agreed");
        expect(userTile).toHaveTextContent("1 Disagreed");
        expect(userTile).toHaveTextContent(/your agreement/i);
    });
});

describe("Legislator — Unresolved Coverage Handling", () => {
    it("renders agreement scores on executive term cards when score data is present while keeping executive stamp", () => {
        const executiveTermWithScores: ILegislatorTermEntry = {
            ...sampleExecutiveTerm,
            district_score: sampleDistrictScore,
            locale_score: sampleLocaleScore,
            user_score: sampleUserScore,
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
        expect(screen.getByTestId("term-charts-toggle-103")).toBeInTheDocument();
    });

    it("renders unvoted term notice alongside district and locale score tiles on executive term when user_score is null", () => {
        const executiveTermWithoutUserScore: ILegislatorTermEntry = {
            ...sampleExecutiveTerm,
            district_score: sampleDistrictScore,
            locale_score: sampleLocaleScore,
            user_score: null,
        };

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [executiveTermWithoutUserScore],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.getByTestId("term-card-executive-stamp")).toBeInTheDocument();
        expect(screen.queryByTestId("executive-office-notice")).not.toBeInTheDocument();
        expect(screen.getByTestId("unvoted-term-notice")).toBeInTheDocument();
        expect(screen.getByTestId("term-district-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-locale-score-tile")).toBeInTheDocument();
        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();
    });

    it("renders an unvoted term message when logged in user has no votes recorded for the term", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2021],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const unvotedNotice = screen.getByTestId("unvoted-term-notice");
        expect(unvotedNotice).toHaveTextContent(/no votes on record for this term/i);

        expect(screen.getByTestId("term-district-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-locale-score-tile")).toBeInTheDocument();
        expect(unvotedNotice).not.toHaveTextContent("0%");
    });

    it("renders an unauthenticated visitor callout prompt when not logged in", () => {
        currentUserMock = null;

        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2025],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const visitorCallout = screen.getByTestId("unauthenticated-history-notice");
        expect(visitorCallout).toHaveTextContent(/sign in|register/i);
        expect(screen.queryByTestId("term-user-score-tile")).not.toBeInTheDocument();

        expect(screen.getByTestId("term-district-score-tile")).toBeInTheDocument();
        expect(screen.getByTestId("term-locale-score-tile")).toBeInTheDocument();
    });
});

describe("Legislator — Record Corrected Badge and Explanation Modal", () => {
    it("renders the Record Corrected badge only when correction_explanation is present", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2025, sampleTerm2021],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        const correctedBadges = screen.getAllByTestId("record-corrected-badge");
        expect(correctedBadges).toHaveLength(1);
        expect(correctedBadges[0]).toHaveTextContent(/record corrected/i);
    });

    it("clicking the Record Corrected badge opens the repair explanation modal with full audit details", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2021],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));

        expect(screen.queryByTestId("historical-repair-modal")).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId("record-corrected-badge"));

        const modal = screen.getByTestId("historical-repair-modal");
        expect(modal).toBeInTheDocument();
        expect(modal).toHaveTextContent("Official Term Date Correction");
        expect(modal).toHaveTextContent("Service dates adjusted per official Maryland General Assembly records.");
        expect(modal).toHaveTextContent("+2");
        expect(modal).toHaveTextContent("term_202");

        const closeButton = screen.getByRole("button", { name: /close|dismiss/i });
        fireEvent.click(closeButton);

        expect(screen.queryByTestId("historical-repair-modal")).not.toBeInTheDocument();
    });
});

describe("Legislator — Read-Only Presentation Integrity", () => {
    it("switching to history tab and interacting with repair modal issues zero router mutations", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleTerm2021],
                }}
            />,
        );

        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        fireEvent.click(screen.getByTestId("record-corrected-badge"));

        expect(routerPostMock).not.toHaveBeenCalled();
        expect(routerPutMock).not.toHaveBeenCalled();
    });
});

const sampleBotmVotes: ILegislatorBillOfTheMonthVote[] = [
    {
        bill_id: 301,
        external_id: "hb-101",
        title: "Clean Water Act",
        scheduled_release_date_utc: "2026-03-01",
        status: "passed",
        legislator_vote: "FOR",
        user_vote: "FOR",
        alignment: "agreed",
    },
    {
        bill_id: 302,
        external_id: "sb-202",
        title: "Transit Funding Act",
        scheduled_release_date_utc: "2026-02-15",
        status: null,
        legislator_vote: "AGAINST",
        user_vote: "FOR",
        alignment: "disagreed",
    },
    {
        bill_id: 303,
        external_id: "hb-303",
        title: "Library Hours Act",
        scheduled_release_date_utc: "2026-01-01",
        status: null,
        legislator_vote: "ABSTAIN",
        user_vote: null,
        alignment: null,
    },
    {
        bill_id: 304,
        external_id: "hb-404",
        title: "Parks Act",
        scheduled_release_date_utc: "2025-12-01",
        status: null,
        legislator_vote: null,
        user_vote: null,
        alignment: null,
    },
];

describe("Legislator — Bill of the Month Voting Record", () => {
    it("renders each bill with uppercased external id, a link to the bill and the representative's vote", () => {
        render(
            <Legislator
                legislator={{ ...baseLegislator, terms: [sampleTerm2025], bill_of_the_month_votes: sampleBotmVotes }}
            />,
        );

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        const items = within(section).getAllByRole("listitem");
        expect(items).toHaveLength(4);

        expect(items[0]).toHaveTextContent("HB-101");
        expect(within(items[0]).getByRole("link", { name: "Clean Water Act" })).toHaveAttribute("href", "/bills/301");
        expect(items[0]).toHaveTextContent("Mar 2026");
        expect(items[0]).toHaveTextContent("Representative vote");
        expect(within(items[0]).getByTestId("botm-legislator-vote-301")).toHaveTextContent("For");
        expect(within(items[1]).getByTestId("botm-legislator-vote-302")).toHaveTextContent("Against");
        expect(within(items[2]).getByTestId("botm-legislator-vote-303")).toHaveTextContent("Abstain");
        expect(within(items[3]).getByTestId("botm-legislator-vote-304")).toHaveTextContent("No vote recorded");
        expect(items[3]).toHaveTextContent("Dec 2025");
    });

    it("labels each release with the month the database holds in a zone west of UTC", () => {
        const original = process.env.TZ;
        process.env.TZ = "America/Los_Angeles";
        try {
            render(
                <Legislator
                    legislator={{
                        ...baseLegislator,
                        terms: [sampleTerm2025],
                        bill_of_the_month_votes: sampleBotmVotes,
                    }}
                />,
            );

            const times = within(screen.getByRole("region", { name: "Bill of the Month Voting Record" }))
                .getAllByRole("listitem")
                .map((item) => item.querySelector("time")?.textContent);
            expect(times).toEqual(["Mar 2026", "Feb 2026", "Jan 2026", "Dec 2025"]);
        } finally {
            process.env.TZ = original;
        }
    });

    it("shows the signed-in user's vote and alignment badges", () => {
        render(
            <Legislator
                legislator={{ ...baseLegislator, terms: [sampleTerm2025], bill_of_the_month_votes: sampleBotmVotes }}
            />,
        );

        const items = within(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).getAllByRole(
            "listitem",
        );
        expect(items[0]).toHaveTextContent("Your vote");
        expect(within(items[0]).getByTestId("botm-user-vote-301")).toHaveTextContent("For");
        expect(within(items[0]).getByTestId("botm-alignment-301")).toHaveTextContent("Agreed");
        expect(within(items[1]).getByTestId("botm-alignment-302")).toHaveTextContent("Disagreed");
        expect(within(items[2]).getByTestId("botm-user-vote-303")).toHaveTextContent("Not voted");
        expect(within(items[2]).queryByTestId("botm-alignment-303")).not.toBeInTheDocument();
    });

    it("omits user vote and alignment badges for anonymous visitors", () => {
        currentUserMock = null;
        render(
            <Legislator
                legislator={{ ...baseLegislator, terms: [sampleTerm2025], bill_of_the_month_votes: sampleBotmVotes }}
            />,
        );

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        expect(section).not.toHaveTextContent("Your vote");
        expect(within(section).queryAllByTestId(/^botm-user-vote-/)).toHaveLength(0);
        expect(within(section).queryAllByTestId(/^botm-alignment-/)).toHaveLength(0);
        expect(within(section).getAllByTestId(/^botm-legislator-vote-/)).toHaveLength(4);
    });

    it("shows the empty state for a voting legislator with no released Bills of the Month", () => {
        render(<Legislator legislator={{ ...baseLegislator, terms: [sampleTerm2025], bill_of_the_month_votes: [] }} />);

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        expect(section).toHaveTextContent("No Bills of the Month have come before this representative yet.");
        expect(within(section).queryAllByRole("listitem")).toHaveLength(0);
    });

    it("shows the empty state when the payload omits bill_of_the_month_votes", () => {
        render(<Legislator legislator={baseLegislator} />);

        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toHaveTextContent(
            "No Bills of the Month have come before this representative yet.",
        );
    });

    it("renders the voting record for an executive office", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleExecutiveTerm],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();
        expect(screen.getByTestId("legislator-botm-record")).toBeInTheDocument();
        expect(screen.getByTestId("botm-record-row-301")).toBeInTheDocument();
    });

    it("renders the empty state for an executive office when bill_of_the_month_votes is empty array", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleExecutiveTerm],
                    bill_of_the_month_votes: [],
                }}
            />,
        );

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        expect(section).toBeInTheDocument();
        expect(section).toHaveTextContent("No Bills of the Month have come before this representative yet.");
        expect(within(section).queryAllByRole("listitem")).toHaveLength(0);
    });

    it("renders the empty state for an executive office when bill_of_the_month_votes is omitted", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleExecutiveTerm],
                }}
            />,
        );

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        expect(section).toBeInTheDocument();
        expect(section).toHaveTextContent("No Bills of the Month have come before this representative yet.");
        expect(within(section).queryAllByRole("listitem")).toHaveLength(0);
    });

    it("shows signed-in user vote and alignment badges for an executive office", () => {
        currentUserMock = { id: 1 };
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleExecutiveTerm],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        expect(section).toHaveTextContent("Your vote");
        expect(within(section).getByTestId("botm-user-vote-301")).toHaveTextContent("For");
        expect(within(section).getByTestId("botm-alignment-301")).toHaveTextContent("Agreed");
        expect(within(section).getByTestId("botm-alignment-302")).toHaveTextContent("Disagreed");
        expect(within(section).getByTestId("botm-user-vote-303")).toHaveTextContent("Not voted");
        expect(within(section).queryByTestId("botm-alignment-303")).not.toBeInTheDocument();
    });

    it("omits user vote and alignment badges for anonymous visitors viewing an executive office", () => {
        currentUserMock = null;
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleExecutiveTerm],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        const section = screen.getByRole("region", { name: "Bill of the Month Voting Record" });
        expect(section).toBeInTheDocument();
        expect(section).not.toHaveTextContent("Your vote");
        expect(within(section).queryAllByTestId(/^botm-user-vote-/)).toHaveLength(0);
        expect(within(section).queryAllByTestId(/^botm-alignment-/)).toHaveLength(0);
        expect(within(section).getAllByTestId(/^botm-legislator-vote-/)).toHaveLength(4);
    });

    it("renders the voting record for an active executive officeholder", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    terms: [sampleActiveExecutiveTerm],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();
        expect(screen.getByTestId("botm-record-row-301")).toBeInTheDocument();
        expect(screen.queryByTestId("legislator-detail-ended-stamp")).not.toBeInTheDocument();
    });

    it("renders the voting record for a former executive officeholder with ended stamp", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: false,
                    terms: [sampleExecutiveTerm],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();
        expect(screen.getByTestId("botm-record-row-301")).toBeInTheDocument();
        expect(screen.getByTestId("legislator-detail-ended-stamp")).toBeInTheDocument();
    });

    it("renders the voting record for a career switcher with mixed legislative and executive terms", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    active: true,
                    terms: [sampleActiveExecutiveTerm, sampleTerm2021],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();
        expect(screen.getByTestId("botm-record-row-301")).toBeInTheDocument();
    });

    it("preserves the voting record visibility across all tab selections for an executive", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    terms: [sampleExecutiveTerm],
                    bill_of_the_month_votes: sampleBotmVotes,
                }}
            />,
        );

        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();

        fireEvent.click(screen.getByRole("tab", { name: "Lifetime" }));
        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();

        fireEvent.click(screen.getByRole("tab", { name: "History" }));
        expect(screen.getByRole("region", { name: "Bill of the Month Voting Record" })).toBeInTheDocument();
    });
});

describe("Legislator — ContactRow external link validation", () => {
    it("does not render legislator-detail-link for a non-http(s) link scheme", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    link: "javascript:alert(1)",
                }}
            />,
        );

        expect(screen.queryByTestId("legislator-detail-link")).not.toBeInTheDocument();
    });

    it("renders legislator-detail-link when link is an https:// URL", () => {
        render(
            <Legislator
                legislator={{
                    ...baseLegislator,
                    link: "https://example.gov",
                }}
            />,
        );

        const link = screen.getByTestId("legislator-detail-link");
        expect(link).toBeInTheDocument();
        expect(link).toHaveAttribute("href", "https://example.gov");
    });
});
