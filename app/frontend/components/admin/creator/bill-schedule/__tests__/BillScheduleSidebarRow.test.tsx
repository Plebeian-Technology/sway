import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { sway } from "sway";
import BillScheduleSidebarRow from "app/frontend/components/admin/creator/bill-schedule/BillScheduleSidebarRow";

const bill: sway.IBillPickerOption = {
    id: 1,
    external_id: "A-1",
    title: "Test Bill",
    scheduled_release_date_utc: "2026-09-08",
    status: null,
    chamber: "council",
    category: "Ordinance",
    introduced_date_time_utc: null,
    latest_action_date_time_utc: null,
    sponsor_name: "",
    legislator_vote_count: 0,
    organization_position_count: 0,
    interesting_badges: [],
    interesting_score_normalized: null,
};

describe("BillScheduleSidebarRow", () => {
    // @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
    it("shows the day the bill is scheduled for, not the day before, in Eastern time", () => {
        const original = process.env.TZ;
        process.env.TZ = "America/New_York";
        try {
            render(
                <BillScheduleSidebarRow
                    bill={bill}
                    selectedBillId={null}
                    date="2026-09-08"
                    onSelectBill={vi.fn<(bill: sway.IBillPickerOption) => void>()}
                />,
            );

            expect(screen.getByText("September 08, 2026")).toBeTruthy();
        } finally {
            process.env.TZ = original;
        }
    });
});
