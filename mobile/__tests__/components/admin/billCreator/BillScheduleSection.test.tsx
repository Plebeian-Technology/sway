import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { patch: (...args: unknown[]) => mockApiPatch(...args) },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import BillScheduleSection from "../../../../src/components/admin/billCreator/BillScheduleSection";
import { dateToCalendarDay } from "../../../../src/utils/calendarDay";

const daysFromToday = (days: number) => {
    const now = new Date();
    return dateToCalendarDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() + days));
};

const unscheduledBill = { id: 42, external_id: "HB1", title: "A Title", scheduled_release_date_utc: null };
const typeDate = (text: string) => fireEvent.changeText(screen.getByTestId("admin-schedule-date-input"), text);

// @lat: [[mobile-bill-creator#Sections#The schedule section]]
describe("BillScheduleSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPatch.mockResolvedValue({});
    });

    it("sends PATCH with the bill id and the chosen day, then reloads", async () => {
        const onChanged = jest.fn();
        const day = daysFromToday(10);
        render(<BillScheduleSection billId={42} bill={unscheduledBill} bills={[]} onChanged={onChanged} />);

        typeDate(day);
        fireEvent.press(screen.getByTestId("admin-schedule-save"));

        await waitFor(() => expect(mockApiPatch).toHaveBeenCalledTimes(1));
        expect(mockApiPatch).toHaveBeenCalledWith("/bill_of_the_month_schedule/42", {
            bill_id: 42,
            scheduled_release_date_utc: day,
        });
        await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    });

    it("keeps Schedule disabled until the date is a real day that is not in the past", () => {
        render(<BillScheduleSection billId={42} bill={unscheduledBill} bills={[]} onChanged={jest.fn()} />);
        const saveDisabled = () => screen.getByTestId("admin-schedule-save").props.accessibilityState.disabled;

        expect(saveDisabled()).toBe(true);
        typeDate("2026-02-31");
        expect(saveDisabled()).toBe(true);
        expect(screen.getByText("Enter a day as YYYY-MM-DD.")).toBeTruthy();
        typeDate("2000-01-01");
        expect(saveDisabled()).toBe(true);
        expect(screen.getByText("Pick a day that is not in the past.")).toBeTruthy();
        typeDate(daysFromToday(0));
        expect(saveDisabled()).toBeFalsy();
    });

    it("refuses a day another bill already holds", () => {
        const day = daysFromToday(10);
        const bills = [{ id: 7, external_id: "HB7", title: "Other", scheduled_release_date_utc: day }];
        render(<BillScheduleSection billId={42} bill={unscheduledBill} bills={bills} onChanged={jest.fn()} />);

        typeDate(day);

        expect(screen.getByText("HB7 is already scheduled for that day.")).toBeTruthy();
        expect(screen.getByTestId("admin-schedule-save").props.accessibilityState.disabled).toBe(true);
    });

    it("offers only Remove for a scheduled bill and sends a null day", async () => {
        const onChanged = jest.fn();
        const bill = { ...unscheduledBill, scheduled_release_date_utc: daysFromToday(10) };
        render(<BillScheduleSection billId={42} bill={bill} bills={[]} onChanged={onChanged} />);

        expect(screen.queryByTestId("admin-schedule-save")).toBeNull();
        expect(screen.getByText("To re-schedule a bill, remove it from the schedule and add it again.")).toBeTruthy();
        fireEvent.press(screen.getByTestId("admin-schedule-remove"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bill_of_the_month_schedule/42", {
                bill_id: 42,
                scheduled_release_date_utc: null,
            }),
        );
        await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    });

    it("shows the server's message when the day was taken in the meantime", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Another bill is already scheduled for that date.",
                undefined,
                422,
            ),
        );
        const onChanged = jest.fn();
        render(<BillScheduleSection billId={42} bill={unscheduledBill} bills={[]} onChanged={onChanged} />);

        typeDate(daysFromToday(10));
        fireEvent.press(screen.getByTestId("admin-schedule-save"));

        expect(await screen.findByText("Another bill is already scheduled for that date.")).toBeTruthy();
        expect(onChanged).not.toHaveBeenCalled();
    });

    it("asks to save a new bill before scheduling it", () => {
        render(<BillScheduleSection billId={null} bill={undefined} bills={[]} onChanged={jest.fn()} />);

        expect(screen.getByText("Save new Bill of the Month before scheduling release date.")).toBeTruthy();
        expect(screen.queryByTestId("admin-schedule-save")).toBeNull();
    });
});
