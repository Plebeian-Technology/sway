import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { sway } from "sway";
import BillPickerRow from "app/frontend/components/admin/creator/BillPickerRow";

// @lat: [[bill-creator-shell#The Bill Creator shell#Why the admin picker sorts by introduction date]]

const baseBill: sway.IBillPickerOption = {
    id: 7,
    external_id: "CB0099",
    title: "Affordable Housing Ordinance",
    scheduled_release_date_utc: null,
    status: "committee",
    chamber: "council",
    category: "Ordinance",
    introduced_date_time_utc: "2026-05-01T12:00:00Z",
    latest_action_date_time_utc: "2026-05-01T12:00:00Z",
    sponsor_name: "Jane Doe",
    legislator_vote_count: 3,
    organization_position_count: 2,
    // Newer fields on IBillPickerOption. This sample bill has no score row
    // yet; the badge and score rendering is covered further down the file.
    interesting_badges: [],
    interesting_score_normalized: null,
};

describe("BillPickerRow", () => {
    it("renders bill number, title, status + chamber badges, sponsor, and tallies", () => {
        render(<BillPickerRow bill={baseBill} />);

        expect(screen.getByText("CB0099")).toBeTruthy();
        expect(screen.getByText("Affordable Housing Ordinance")).toBeTruthy();
        expect(screen.getByText("committee")).toBeTruthy();
        expect(screen.getByText("council")).toBeTruthy();
        expect(screen.getByText(/Jane Doe/)).toBeTruthy();
        expect(screen.getByText(/3 votes/)).toBeTruthy();
        expect(screen.getByText(/2 positions/)).toBeTruthy();
    });

    it("singularizes a single vote / position", () => {
        render(<BillPickerRow bill={{ ...baseBill, legislator_vote_count: 1, organization_position_count: 1 }} />);

        expect(screen.getByText(/1 vote(?!s)/)).toBeTruthy();
        expect(screen.getByText(/1 position(?!s)/)).toBeTruthy();
    });

    // @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
    it("shows the day the bill is scheduled for, not the day before, in Eastern time", () => {
        const original = process.env.TZ;
        process.env.TZ = "America/New_York";
        try {
            render(<BillPickerRow bill={{ ...baseBill, scheduled_release_date_utc: "2026-09-08" }} />);

            expect(screen.getByText(/Scheduled September 08, 2026/)).toBeTruthy();
        } finally {
            process.env.TZ = original;
        }
    });

    it("omits zero tallies and an absent scheduled date", () => {
        render(
            <BillPickerRow
                bill={{
                    ...baseBill,
                    scheduled_release_date_utc: null,
                    legislator_vote_count: 0,
                    organization_position_count: 0,
                }}
            />,
        );

        expect(screen.queryByText(/votes?/)).toBeNull();
        expect(screen.queryByText(/positions?/)).toBeNull();
        expect(screen.queryByText(/Scheduled/)).toBeNull();
    });
});

// @lat: [[picker-bills-serializer-design#BillPickerRow.test.tsx notes]]
describe("BillPickerRow signal badges", () => {
    it("renders all three badges in fixed order controversial -> close -> live", () => {
        render(<BillPickerRow bill={{ ...baseBill, interesting_badges: ["controversial", "close", "live"] }} />);

        const badges = screen.getAllByText(/^(Split|Narrow|Live)$/);
        expect(badges.map((b) => b.textContent)).toEqual(["Split", "Narrow", "Live"]);
    });

    it("renders only the badges present, still in fixed order regardless of source array order", () => {
        render(<BillPickerRow bill={{ ...baseBill, interesting_badges: ["live", "controversial"] }} />);

        const badges = screen.getAllByText(/^(Split|Narrow|Live)$/);
        expect(badges.map((b) => b.textContent)).toEqual(["Split", "Live"]);
        expect(screen.queryByText("Narrow")).toBeNull();
    });

    it("renders no signal badges when interesting_badges is empty", () => {
        render(<BillPickerRow bill={{ ...baseBill, interesting_badges: [] }} />);

        expect(screen.queryByText("Split")).toBeNull();
        expect(screen.queryByText("Narrow")).toBeNull();
        expect(screen.queryByText("Live")).toBeNull();
    });

    it("renders no signal badges for a bill with no score row yet (null normalized score)", () => {
        render(<BillPickerRow bill={{ ...baseBill, interesting_score_normalized: null, interesting_badges: [] }} />);

        expect(screen.queryByText("Split")).toBeNull();
        expect(screen.queryByText("Narrow")).toBeNull();
        expect(screen.queryByText("Live")).toBeNull();
    });

    it("a Baltimore-style bill (council chamber) never renders Narrow, even alongside other signals", () => {
        render(
            <BillPickerRow bill={{ ...baseBill, chamber: "council", interesting_badges: ["controversial", "live"] }} />,
        );

        expect(screen.getByText("Split")).toBeTruthy();
        expect(screen.getByText("Live")).toBeTruthy();
        expect(screen.queryByText("Narrow")).toBeNull();
    });

    it("applies the exact Copywriting Contract title strings to each signal badge", () => {
        render(<BillPickerRow bill={{ ...baseBill, interesting_badges: ["controversial", "close", "live"] }} />);

        expect(screen.getByText("Split").getAttribute("title")).toBe(
            "Cross-party defection or organization position split",
        );
        expect(screen.getByText("Narrow").getAttribute("title")).toBe(
            "Close final-vote margin (Congress and Maryland only)",
        );
        expect(screen.getByText("Live").getAttribute("title")).toBe("Recent legislative activity within 30 days");
    });

    it("status and chamber badges are unaffected by signal badges", () => {
        render(<BillPickerRow bill={{ ...baseBill, interesting_badges: ["controversial", "close", "live"] }} />);

        expect(screen.getByText("committee")).toBeTruthy();
        expect(screen.getByText("council")).toBeTruthy();
    });
});
