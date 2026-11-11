// Clearing the input must call setData(..., null), not return early — the input is controlled
// (value={dateString}), so an early return snaps the box back to the previous date.

import { fireEvent, render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));

import DateField from "app/frontend/components/admin/creator/fields/DateField";

const withdrawnField = {
    name: "withdrawn_date_time_utc" as const,
    component: "date" as const,
    type: "date" as const,
    label: "Withdrawn Date",
    isRequired: false,
};

const renderWithFormContext = (setData: ReturnType<typeof vi.fn>, data: Record<string, unknown>) => {
    const formValue = {
        data,
        setData,
        errors: {},
        processing: false,
    } as unknown as React.ContextType<typeof SwayFormContext>;

    return render(
        <SwayFormContext.Provider value={formValue}>
            <DateField swayField={withdrawnField} />
        </SwayFormContext.Provider>,
    );
};

describe("DateField — clearing to null", () => {
    it("persists null when the date input is cleared", () => {
        const setData = vi.fn<(key: string, value: unknown) => void>();
        const { container } = renderWithFormContext(setData, {
            withdrawn_date_time_utc: "2026-01-02T00:00:00.000Z",
        });

        const input = container.querySelector("#withdrawn_date_time_utc") as HTMLInputElement;
        expect(input.value).toBe("2026-01-02");

        fireEvent.change(input, { target: { value: "" } });

        expect(setData).toHaveBeenCalledWith("withdrawn_date_time_utc", null);
    });

    it("persists an ISO string when a valid date is entered", () => {
        const setData = vi.fn<(key: string, value: unknown) => void>();
        const { container } = renderWithFormContext(setData, {});

        const input = container.querySelector("#withdrawn_date_time_utc") as HTMLInputElement;
        fireEvent.change(input, { target: { value: "2026-03-04" } });

        expect(setData).toHaveBeenCalledWith("withdrawn_date_time_utc", expect.stringContaining("2026-03-04"));
    });
});
