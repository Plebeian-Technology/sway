import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { groupScore, suppressedGroupScore } from "app/frontend/__tests__/support/groupScore";
import type { ILegislatorTermEntry } from "app/frontend/types/legislators";

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
}));
vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => ({ id: 1, invite_url: null }),
}));

import LegislatorTermCard from "app/frontend/components/legislators/history/LegislatorTermCard";

const legislator = {
    id: 11,
    full_name: "Jane Doe",
    district: { name: "MD3", number: 3 },
} as unknown as sway.ILegislator;

const term = (overrides: Partial<ILegislatorTermEntry>): ILegislatorTermEntry => ({
    id: 5,
    session_label: "2025–2027 Council",
    term_start_year: 2025,
    term_end_year: 2027,
    began_on: null,
    ended_on: null,
    district_name: "MD3",
    is_executive: false,
    active: true,
    district_score: null,
    locale_score: null,
    user_score: { count_agreed: 4, count_disagreed: 1, count_no_legislator_vote: 0, count_legislator_abstained: 0 },
    correction_explanation: null,
    ...overrides,
});

const bigCounters = {
    count_agreed: 4321,
    count_disagreed: 1234,
    count_no_legislator_vote: 0,
    count_legislator_abstained: 0,
};

afterEach(cleanup);

// @lat: [[voter-privacy-threshold#Legislator charts draw percentages or the placeholder]]
describe("LegislatorTermCard at the ten-voter minimum", () => {
    it("says 'Not enough votes yet' on a suppressed district tile and shows no counter", () => {
        render(
            <LegislatorTermCard
                legislator={legislator}
                term={term({
                    district_score: { ...bigCounters, ...suppressedGroupScore() },
                    locale_score: groupScore(bigCounters),
                })}
            />,
        );

        const districtTile = screen.getByTestId("term-district-score-tile");
        expect(districtTile).toHaveTextContent("Not enough votes yet");
        expect(districtTile.textContent).not.toMatch(/4,?321|1,?234|%/);
    });

    it("draws an unsuppressed locale tile from percentages and shows no counter", () => {
        render(
            <LegislatorTermCard
                legislator={legislator}
                term={term({
                    district_score: { ...bigCounters, ...suppressedGroupScore() },
                    locale_score: groupScore(bigCounters),
                })}
            />,
        );

        const localeTile = screen.getByTestId("term-locale-score-tile");
        expect(localeTile).toHaveTextContent("78% Agreed");
        expect(localeTile).toHaveTextContent("22% Disagreed");
        expect(localeTile.textContent).not.toMatch(/4,?321|1,?234/);
    });

    it("headlines each tile with the server's agreed share of agreed and disagreed pairs", () => {
        render(
            <LegislatorTermCard
                legislator={legislator}
                term={term({
                    district_score: {
                        comparison_suppressed: false,
                        agreed_percent: 1,
                        disagreed_percent: 0,
                        no_legislator_vote_percent: 99,
                        legislator_abstained_percent: 0,
                        voter_agreement_percent: 60,
                    },
                    locale_score: {
                        comparison_suppressed: false,
                        agreed_percent: 0,
                        disagreed_percent: 0,
                        no_legislator_vote_percent: 100,
                        legislator_abstained_percent: 0,
                        voter_agreement_percent: 50,
                    },
                })}
            />,
        );

        expect(screen.getByTestId("term-district-score-tile")).toHaveTextContent("60%");
        expect(screen.getByTestId("term-district-score-tile")).not.toHaveTextContent("100%");
        expect(screen.getByTestId("term-locale-score-tile")).toHaveTextContent("50%");
        expect(screen.getByTestId("term-locale-score-tile")).not.toHaveTextContent("--%");
    });

    it("says 'Not enough votes yet' on a tile whose score was not sent", () => {
        render(<LegislatorTermCard legislator={legislator} term={term({})} />);

        expect(screen.getByTestId("term-locale-score-tile")).toHaveTextContent("Not enough votes yet");
    });

    it("keeps the reader's own counts on the card", () => {
        render(<LegislatorTermCard legislator={legislator} term={term({})} />);

        expect(screen.getByText("4 Agreed")).toBeInTheDocument();
        expect(screen.getByText("1 Disagreed")).toBeInTheDocument();
    });

    it("shows the placeholder in the term charts for a suppressed score", () => {
        render(
            <LegislatorTermCard
                legislator={legislator}
                term={term({
                    district_score: { ...bigCounters, ...suppressedGroupScore() },
                    locale_score: groupScore(bigCounters),
                })}
            />,
        );

        fireEvent.click(screen.getByTestId("term-charts-toggle-5"));

        expect(screen.getAllByTestId("voter-district-agreement-chart-suppressed")).toHaveLength(1);
        expect(screen.getAllByTestId("voter-district-agreement-chart")).toHaveLength(1);
    });
});
