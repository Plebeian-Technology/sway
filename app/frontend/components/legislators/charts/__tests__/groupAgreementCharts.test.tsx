import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
}));
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));
vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => ({ id: 1, invite_url: "https://app.example.test/invite/1/abc" }),
}));

import LegislatorChartsPanel from "app/frontend/components/legislators/charts/LegislatorChartsPanel";
import VoterDistrictAgreementChart from "app/frontend/components/legislators/charts/VoterDistrictAgreementChart";

const counters = {
    count_agreed: 4321,
    count_disagreed: 1234,
    count_no_legislator_vote: 0,
    count_legislator_abstained: 0,
};

const shown: sway.scoring.ILegislatorDistrictScore = {
    ...counters,
    legislator_id: 11,
    comparison_suppressed: false,
    agreed_percent: 62,
    disagreed_percent: 30,
    no_legislator_vote_percent: 8,
    legislator_abstained_percent: 0,
};

const hidden: sway.scoring.ILegislatorDistrictScore = {
    ...counters,
    legislator_id: 11,
    comparison_suppressed: true,
    agreed_percent: null,
    disagreed_percent: null,
    no_legislator_vote_percent: null,
    legislator_abstained_percent: null,
};

const ownScore = { count_agreed: 5, count_disagreed: 2, count_no_legislator_vote: 1, count_legislator_abstained: 0 };

const legislatorWith = (
    district: sway.scoring.ILegislatorDistrictScore,
    locale: sway.scoring.ILegislatorDistrictScore,
): sway.ILegislator => {
    const score = {
        ...ownScore,
        user_legislator_id: 1,
        legislator_id: 11,
        sway_locale_id: 2,
        legislator_district_score: district,
        legislator_locale_score: locale,
    };
    return {
        id: 11,
        full_name: "Jane Doe",
        district: { id: 3, number: 7, region_code: "MD" },
        user_legislator_score: score,
        lifetime_score: score,
    } as unknown as sway.ILegislator;
};

afterEach(cleanup);

// @lat: [[voter-privacy-threshold#Legislator charts draw percentages or the placeholder]]
describe("VoterDistrictAgreementChart", () => {
    it("draws an unsuppressed score from its percentages and shows no raw counter", () => {
        render(<VoterDistrictAgreementChart scores={shown} title="District 7 agreement" />);

        const chart = screen.getByTestId("voter-district-agreement-chart");
        expect(chart).toHaveTextContent("62%");
        expect(chart).toHaveTextContent("30%");
        expect(chart.textContent).not.toMatch(/4,?321|1,?234/);
    });

    it("shows the placeholder and no chart for a suppressed score", () => {
        render(<VoterDistrictAgreementChart scores={hidden} title="District 7 agreement" />);

        expect(screen.queryByTestId("voter-district-agreement-chart")).toBeNull();
        const placeholder = screen.getByTestId("voter-district-agreement-chart-suppressed");
        expect(placeholder).toHaveTextContent("District 7 agreement");
        expect(placeholder).toHaveTextContent("Not enough votes yet");
        expect(placeholder.textContent).not.toMatch(/4,?321|1,?234|%/);
    });

    it("treats a score with no flag as suppressed", () => {
        render(<VoterDistrictAgreementChart scores={counters as unknown as sway.scoring.ILegislatorDistrictScore} />);

        expect(screen.queryByTestId("voter-district-agreement-chart")).toBeNull();
        expect(screen.getByText("Not enough votes yet")).toBeInTheDocument();
    });
});

describe("LegislatorChartsPanel at the ten-voter minimum", () => {
    it("shows the placeholder for a suppressed district score beside a drawn locale score", () => {
        render(<LegislatorChartsPanel legislator={legislatorWith(hidden, shown)} />);

        expect(screen.getAllByTestId("voter-district-agreement-chart-suppressed")).toHaveLength(1);
        expect(screen.getAllByTestId("voter-district-agreement-chart")).toHaveLength(1);
    });

    it("shows the placeholder for a suppressed locale score", () => {
        render(<LegislatorChartsPanel legislator={legislatorWith(shown, hidden)} />);

        const placeholder = screen.getByTestId("voter-district-agreement-chart-suppressed");
        expect(placeholder).toHaveTextContent("Baltimore, Maryland agreement with Jane Doe");
    });

    it("shows placeholders and no chart for suppressed lifetime scores", () => {
        render(<LegislatorChartsPanel legislator={legislatorWith(hidden, hidden)} mode="lifetime" />);

        expect(screen.getAllByTestId("voter-district-agreement-chart-suppressed")).toHaveLength(2);
        expect(screen.queryByTestId("voter-district-agreement-chart")).toBeNull();
    });

    it("draws the reader's own agreement from its counters whatever the group scores say", () => {
        render(<LegislatorChartsPanel legislator={legislatorWith(hidden, hidden)} />);

        const ownChart = screen.getByTestId("voter-agreement-chart");
        expect(within(ownChart).getByText("5")).toBeInTheDocument();
        expect(within(ownChart).getByText("2")).toBeInTheDocument();
    });
});
