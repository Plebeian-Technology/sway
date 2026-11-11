import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

import UserAddressChanges, { type UserAddressChangeRow } from "app/frontend/pages/admin/UserAddressChanges";

const sampleRows: UserAddressChangeRow[] = [
    {
        id: 101,
        user_id: 42,
        previous_address_id: 10,
        new_address_id: 11,
        deactivated_legislator_ids: [1, 2],
        activated_legislator_ids: [3, 4],
        deactivated_district_ids: [100],
        activated_district_ids: [200],
        previous_sway_locale_ids: [10],
        new_sway_locale_ids: [20],
        previous_sway_locale_names: ["baltimore-maryland-united_states"],
        new_sway_locale_names: ["annapolis-maryland-united_states"],
        prior_vote_count: 3,
        prior_voted_bill_ids: [501, 502, 503],
        prior_voted_sway_locale_ids: [10],
        cross_district: true,
        cross_sway_locale: true,
        voted_before_switch: true,
        user_switch_count: 2,
        created_at: "2026-11-08T12:00:00Z",
    },
    {
        id: 100,
        user_id: 99,
        previous_address_id: 5,
        new_address_id: 6,
        deactivated_legislator_ids: [1],
        activated_legislator_ids: [1],
        deactivated_district_ids: [100],
        activated_district_ids: [100],
        previous_sway_locale_ids: [10],
        new_sway_locale_ids: [10],
        previous_sway_locale_names: ["baltimore-maryland-united_states"],
        new_sway_locale_names: ["baltimore-maryland-united_states"],
        prior_vote_count: 0,
        prior_voted_bill_ids: [],
        prior_voted_sway_locale_ids: [],
        cross_district: false,
        cross_sway_locale: false,
        voted_before_switch: false,
        user_switch_count: 1,
        created_at: "2026-11-07T09:30:00Z",
    },
];

afterEach(cleanup);

describe("admin/UserAddressChanges", () => {
    it("renders the heading, total count, and audit details including warning badges", () => {
        render(<UserAddressChanges user_address_changes={sampleRows} />);

        expect(screen.getByRole("heading", { level: 1, name: "Address Changes" })).toBeInTheDocument();
        expect(screen.getByText("2 switches")).toBeInTheDocument();

        expect(screen.getByText("User #42")).toBeInTheDocument();
        expect(screen.getByText("2 switches total")).toBeInTheDocument();
        expect(screen.getByText("Repeat switcher")).toBeInTheDocument();
        expect(screen.getByText("Cross-district")).toBeInTheDocument();
        expect(screen.getByText("Cross-locale")).toBeInTheDocument();
        expect(screen.getByText("Voted before switch")).toBeInTheDocument();

        expect(screen.getByText("Address #10 -> #11")).toBeInTheDocument();
        expect(
            screen.getByText("baltimore-maryland-united_states -> annapolis-maryland-united_states"),
        ).toBeInTheDocument();
        expect(screen.getByText("100 -> 200")).toBeInTheDocument();
        expect(screen.getByText("1, 2 -> 3, 4")).toBeInTheDocument();
        expect(screen.getByText("3 votes (Bills: 501, 502, 503)")).toBeInTheDocument();

        expect(screen.getByText("User #99")).toBeInTheDocument();
        expect(screen.getByText("1 switch total")).toBeInTheDocument();
        expect(screen.getByText("Address #5 -> #6")).toBeInTheDocument();
        expect(screen.getByText("0 votes")).toBeInTheDocument();
    });

    it("renders the empty state when no address switches have been recorded", () => {
        render(<UserAddressChanges user_address_changes={[]} />);

        expect(screen.getByRole("heading", { level: 1, name: "Address Changes" })).toBeInTheDocument();
        expect(screen.getByText("0 switches")).toBeInTheDocument();
        expect(screen.getByText("No user address switches have been recorded.")).toBeInTheDocument();
    });

    it("pluralizes a single recorded switch and single prior vote", () => {
        render(
            <UserAddressChanges
                user_address_changes={[
                    {
                        ...sampleRows[1],
                        prior_vote_count: 1,
                        prior_voted_bill_ids: [777],
                        voted_before_switch: true,
                    },
                ]}
            />,
        );

        expect(screen.getByText("1 switch")).toBeInTheDocument();
        expect(screen.getByText("1 vote (Bills: 777)")).toBeInTheDocument();
        expect(screen.getByText("Voted before switch")).toBeInTheDocument();
        expect(screen.queryByText("Repeat switcher")).not.toBeInTheDocument();
        expect(screen.queryByText("Cross-district")).not.toBeInTheDocument();
        expect(screen.queryByText("Cross-locale")).not.toBeInTheDocument();
    });
});
