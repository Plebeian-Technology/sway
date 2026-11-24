import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const reloadMock = vi.fn<(options?: unknown) => void>();
let mockPageProps: Record<string, unknown> = {};

vi.mock("@inertiajs/react", () => ({
    router: { reload: (options?: unknown) => reloadMock(options) },
    usePage: () => ({ props: mockPageProps }),
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
}));

import BillAffinityPanel from "app/frontend/components/bill/charts/BillAffinityPanel";
import BillChartsPanel from "app/frontend/components/bill/charts/BillChartsPanel";

const district = (number: number): sway.IDistrict =>
    ({ name: `D-${number}`, number, region_code: "D" }) as sway.IDistrict;

const BILL = { id: 42, title: "Street Trees Act" } as unknown as sway.IBill;

// 30 voters: 12 in district 4, 4 in district 7, and the at-large row repeating the total.
const SCORE: sway.IBillScore = {
    bill_id: 42,
    for: 18,
    against: 12,
    comparison_suppressed: false,
    voters_needed: 0,
    districts: [
        { district: district(0), comparison_suppressed: false, for_percent: 60, against_percent: 40, at_large: true },
        { district: district(4), comparison_suppressed: false, for_percent: 75, against_percent: 25, at_large: false },
        {
            district: district(7),
            comparison_suppressed: true,
            for_percent: null,
            against_percent: null,
            at_large: false,
        },
    ],
};

// @lat: [[bill-vote-charts-design#DistrictVotesChart.tsx]]
describe("district charts at the ten-voter minimum", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        mockPageProps = { user: { id: 1 }, legislators: [], districts: [district(7)] };
    });

    afterEach(cleanup);

    it("draws a district with ten voters as percentage bars with no count", () => {
        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        const chart = screen.getByTestId("district-votes-chart");
        expect(within(chart).getByLabelText("District 4 support 75%")).toBeInTheDocument();
        expect(within(chart).getByLabelText("District 4 oppose 25%")).toBeInTheDocument();
        expect(chart).toHaveTextContent("75%");
        expect(chart).toHaveTextContent("25%");
        expect(chart.textContent).not.toMatch(/\b(9|3|12)\b/);
    });

    it("keeps the exact bill total above the district bars", () => {
        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        expect(screen.getByLabelText("18 support, 12 oppose")).toBeInTheDocument();
    });

    it("does not draw the at-large row", () => {
        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        expect(screen.getByTestId("district-votes-chart")).not.toHaveTextContent("District 0");
    });

    it("says 'Not enough votes yet' for the reader's own district when it is under the minimum", () => {
        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        const row = screen.getByTestId("district-votes-chart-reader-district-7");
        expect(row).toHaveTextContent("District 7");
        expect(row).toHaveTextContent("Not enough votes yet");
        expect(screen.queryByLabelText(/District 7 support/)).toBeNull();
    });

    it("says 'Not enough votes yet' for the reader's own district when the server sent no row for it", () => {
        mockPageProps = { user: { id: 1 }, legislators: [], districts: [district(9)] };

        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        expect(screen.getByTestId("district-votes-chart-reader-district-9")).toHaveTextContent("Not enough votes yet");
    });

    it("draws no other district that is under the minimum", () => {
        mockPageProps = { user: { id: 1 }, legislators: [], districts: [district(4)] };

        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        expect(screen.getByTestId("district-votes-chart")).not.toHaveTextContent("District 7");
    });

    it("asks the server once for a signed-in reader's districts when the page has none", () => {
        mockPageProps = { user: { id: 1 }, legislators: [] };

        render(<BillChartsPanel bill={BILL} bill_score={SCORE} />);

        expect(reloadMock).toHaveBeenCalledTimes(1);
        expect(reloadMock).toHaveBeenCalledWith({ only: ["districts"] });
    });

    it("draws the affinity chart from percentages, without the hidden or at-large districts", () => {
        render(<BillAffinityPanel bill_score={SCORE} />);

        const chart = screen.getByTestId("affinity-district-chart");
        expect(chart).toHaveTextContent("D-4 (+50%)");
        expect(chart).not.toHaveTextContent("D-7");
        expect(chart).not.toHaveTextContent("D-0");
    });

    it("draws neither panel while the bill tally is suppressed", () => {
        const suppressed = { ...SCORE, for: null, against: null, comparison_suppressed: true, voters_needed: 3 };

        const { container } = render(
            <>
                <BillChartsPanel bill={BILL} bill_score={suppressed} />
                <BillAffinityPanel bill_score={suppressed} />
            </>,
        );

        expect(container).toBeEmptyDOMElement();
    });
});
