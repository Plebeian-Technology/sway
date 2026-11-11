import { render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { sway } from "sway";

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));
vi.mock("app/frontend/components/legislators/charts/VoterAgreementChart", () => ({
    __esModule: true,
    default: ({ title }: { title?: string }) => <div data-testid="user-chart">{title}</div>,
}));
vi.mock("app/frontend/components/legislators/charts/VoterDistrictAgreementChart", () => ({
    __esModule: true,
    default: ({ title }: { title?: string }) => <div data-testid="district-chart">{title}</div>,
}));

import LegislatorChartsPanel from "app/frontend/components/legislators/charts/LegislatorChartsPanel";

const scores = {
    count_agreed: 4,
    count_disagreed: 1,
    count_no_legislator_vote: 0,
    count_legislator_abstained: 0,
};

const legislator = {
    id: 11,
    full_name: "Jane Doe",
    district: { id: 3, number: 7, region_code: "MD" },
    user_legislator_score: {
        ...scores,
        user_legislator_id: 1,
        legislator_id: 11,
        sway_locale_id: 2,
        legislator_district_score: { ...scores, legislator_id: 11 },
        legislator_locale_score: { ...scores, legislator_id: 11 },
    },
    lifetime_score: {
        ...scores,
        user_legislator_id: 1,
        legislator_id: 11,
        sway_locale_id: 2,
        legislator_district_score: { ...scores, legislator_id: 11 },
        legislator_locale_score: { ...scores, legislator_id: 11 },
    },
} as unknown as sway.ILegislator;

describe("LegislatorChartsPanel captions", () => {
    it("names the viewer, the district and the locale in current mode", () => {
        const { getByTestId, getAllByTestId } = render(<LegislatorChartsPanel legislator={legislator} />);

        const districtCharts = getAllByTestId("district-chart");

        expect(getByTestId("user-chart").textContent).toBe("Your agreement with Jane Doe");
        expect(districtCharts[0].textContent).toBe("District 7 agreement with Jane Doe");
        expect(districtCharts[1].textContent).toBe("Baltimore, Maryland agreement with Jane Doe");
    });

    it("marks all three captions as lifetime in lifetime mode", () => {
        const { getByTestId, getAllByTestId } = render(
            <LegislatorChartsPanel legislator={legislator} mode="lifetime" />,
        );

        const districtCharts = getAllByTestId("district-chart");

        expect(getByTestId("user-chart").textContent).toBe("Your agreement with Jane Doe · lifetime");
        expect(districtCharts[0].textContent).toBe("All districts · lifetime agreement with Jane Doe");
        expect(districtCharts[1].textContent).toBe("Baltimore, Maryland · lifetime agreement with Jane Doe");
    });
});
