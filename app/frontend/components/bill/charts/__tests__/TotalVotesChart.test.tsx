import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { sway } from "sway";

import TotalVotesChart from "app/frontend/components/bill/charts/TotalVotesChart";

const score = (overrides: Partial<sway.IBillScore>): sway.IBillScore => ({
    bill_id: 42,
    for: 7777,
    against: 4321,
    for_percent: 70,
    against_percent: 30,
    comparison_suppressed: false,
    voters_needed: 0,
    districts: [],
    ...overrides,
});

// @lat: [[bill-vote-charts-design#TotalVotesChart.tsx]]
describe("TotalVotesChart", () => {
    afterEach(cleanup);

    it("shows the For and Against percentages and no count in text, aria-label or title", () => {
        const { container } = render(<TotalVotesChart score={score({})} title="All votes" />);

        expect(screen.getByTestId("total-votes-chart")).toHaveTextContent("70%");
        expect(screen.getByTestId("total-votes-chart")).toHaveTextContent("30%");
        expect(container.innerHTML).not.toMatch(/7,?777|4,?321/);
        expect(container.querySelector("[aria-label]")?.getAttribute("aria-label")).toBe("70% support, 30% oppose");
    });

    it("sizes the bar segments by the percentages", () => {
        const { container } = render(<TotalVotesChart score={score({})} />);

        const widths = Array.from(container.querySelectorAll<HTMLElement>("[aria-label] > div")).map(
            (segment) => segment.style.width,
        );
        expect(widths).toEqual(["70%", "30%"]);
    });

    it("says no votes are recorded when no percentage is published", () => {
        render(<TotalVotesChart score={score({ for_percent: null, against_percent: null })} />);

        expect(screen.getByTestId("total-votes-chart-empty")).toHaveTextContent("No votes recorded yet.");
    });
});
