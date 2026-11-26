import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import ScheduledBillsSection from "../../../../src/components/admin/billCreator/ScheduledBillsSection";
import { dateToCalendarDay } from "../../../../src/utils/calendarDay";

const dayInMonths = (months: number, day: number) => {
    const now = new Date();
    return dateToCalendarDay(new Date(now.getFullYear(), now.getMonth() + months, day));
};

const bill = (id: number, date: string | null) => ({
    id,
    external_id: `HB${id}`,
    title: `Title ${id}`,
    scheduled_release_date_utc: date,
});

// @lat: [[mobile-bill-creator#Sections#The schedule section]]
describe("ScheduledBillsSection", () => {
    it("groups upcoming bills by month, earliest first, and opens one when pressed", () => {
        const onSelectBill = jest.fn();
        const later = bill(2, dayInMonths(2, 5));
        const sooner = bill(1, dayInMonths(1, 20));
        render(<ScheduledBillsSection bills={[later, sooner]} selectedBillId={null} onSelectBill={onSelectBill} />);

        const headers = screen.getAllByTestId(/^admin-schedule-month-/);
        expect(headers).toHaveLength(2);
        const rows = screen.getAllByTestId(/^admin-schedule-row-/);
        expect(rows.map((row) => row.props.testID)).toEqual(["admin-schedule-row-1", "admin-schedule-row-2"]);

        fireEvent.press(screen.getByTestId("admin-schedule-row-2"));
        expect(onSelectBill).toHaveBeenCalledWith(later);
    });

    it("says so when nothing is scheduled ahead", () => {
        render(<ScheduledBillsSection bills={[bill(1, null)]} selectedBillId={null} onSelectBill={jest.fn()} />);

        expect(screen.getByText("No scheduled bills. Pick a future day for this bill.")).toBeTruthy();
    });

    it("lists past bills five at a time, newest first, with the full count", () => {
        const past = Array.from({ length: 7 }, (_, i) => bill(i + 1, dayInMonths(-1, i + 1)));
        render(<ScheduledBillsSection bills={past} selectedBillId={null} onSelectBill={jest.fn()} />);

        expect(screen.getByText("Past scheduled (7)")).toBeTruthy();
        expect(screen.getAllByTestId(/^admin-schedule-row-/).map((row) => row.props.testID)).toEqual([
            "admin-schedule-row-7",
            "admin-schedule-row-6",
            "admin-schedule-row-5",
            "admin-schedule-row-4",
            "admin-schedule-row-3",
        ]);

        fireEvent.press(screen.getByTestId("admin-schedule-past-more"));
        expect(screen.getAllByTestId(/^admin-schedule-row-/)).toHaveLength(7);
        expect(screen.queryByTestId("admin-schedule-past-more")).toBeNull();
    });

    it("keeps unscheduled bills collapsed until opened, five at a time", () => {
        const unscheduled = Array.from({ length: 6 }, (_, i) => bill(i + 1, null));
        render(<ScheduledBillsSection bills={unscheduled} selectedBillId={null} onSelectBill={jest.fn()} />);

        expect(screen.getByText("Unscheduled (6)")).toBeTruthy();
        expect(screen.queryByTestId("admin-schedule-row-1")).toBeNull();

        fireEvent.press(screen.getByTestId("admin-schedule-unscheduled-toggle"));
        expect(screen.getAllByTestId(/^admin-schedule-row-/)).toHaveLength(5);
        fireEvent.press(screen.getByTestId("admin-schedule-unscheduled-more"));
        expect(screen.getAllByTestId(/^admin-schedule-row-/)).toHaveLength(6);
    });

    it("marks the bill being edited and does not reopen it", () => {
        const onSelectBill = jest.fn();
        render(
            <ScheduledBillsSection
                bills={[bill(1, dayInMonths(1, 20))]}
                selectedBillId={1}
                onSelectBill={onSelectBill}
            />,
        );

        expect(screen.getByText("Selected")).toBeTruthy();
        fireEvent.press(screen.getByTestId("admin-schedule-row-1"));
        expect(onSelectBill).not.toHaveBeenCalled();
    });
});
