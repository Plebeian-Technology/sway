import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import PerBillGridSection, {
    type PerBillGridRun,
} from "../../../../src/components/admin/billCreator/PerBillGridSection";

const runBill = (externalId: string, status: string, overrides: Record<string, unknown> = {}) => ({
    bill_external_id: externalId,
    title: `Title ${externalId}`,
    status,
    started_at: "2026-11-24T11:30:00Z",
    finished_at: null,
    error_message: null,
    sort_order: 1,
    ...overrides,
});

const allBillsRun = (overrides: Partial<PerBillGridRun> = {}): PerBillGridRun => ({
    kind: "all_bills",
    status: "running",
    current_stage: "extract-text",
    pipeline_run_stages: [{ status: "succeeded" }, { status: "running" }, { status: "pending" }],
    pipeline_run_bills: [runBill("25-0001", "running"), runBill("25-0002", "failed", { started_at: null })],
    ...overrides,
});

const open = () => fireEvent.press(screen.getByTestId("admin-per-bill-grid-toggle"));

// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
describe("PerBillGridSection", () => {
    beforeEach(() => {
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => jest.useRealTimers());

    it("shows nothing without a run or for a single-bill run", () => {
        const { toJSON, rerender } = render(<PerBillGridSection run={null} currentBillExternalId="25-0001" />);
        expect(toJSON()).toBeNull();

        rerender(<PerBillGridSection run={allBillsRun({ kind: "single" })} currentBillExternalId="25-0001" />);
        expect(toJSON()).toBeNull();
    });

    it("lists each bill with status, stage, stages done, and start time", () => {
        render(<PerBillGridSection run={allBillsRun()} currentBillExternalId="" />);
        open();

        const first = screen.getByTestId("admin-per-bill-grid-row-25-0001");
        expect(first).toHaveTextContent(/Title 25-0001/);
        expect(first).toHaveTextContent(/25-0001/);
        expect(first).toHaveTextContent(/running/);
        expect(first).toHaveTextContent(/Stage extract-text/);
        expect(first).toHaveTextContent(/1\/3 stages/);
        expect(first).toHaveTextContent(/Started 30m ago/);
        const second = screen.getByTestId("admin-per-bill-grid-row-25-0002");
        expect(second).toHaveTextContent(/failed/);
        expect(second).toHaveTextContent(/Started —/);
    });

    it("falls back to the external id when a bill has no title", () => {
        render(
            <PerBillGridSection
                run={allBillsRun({ pipeline_run_bills: [runBill("25-0003", "pending", { title: null })] })}
                currentBillExternalId=""
            />,
        );
        open();

        expect(screen.getByTestId("admin-per-bill-grid-row-25-0003")).toHaveTextContent(/25-0003/);
    });

    it("shows a dash for the stage once the run is finished", () => {
        render(<PerBillGridSection run={allBillsRun({ status: "completed" })} currentBillExternalId="" />);
        open();

        expect(screen.getByTestId("admin-per-bill-grid-row-25-0001")).toHaveTextContent(/Stage —/);
    });

    it("lists the bill being edited first and marks it", () => {
        render(<PerBillGridSection run={allBillsRun()} currentBillExternalId="25-0002" />);
        open();

        const rows = screen.getAllByTestId(/^admin-per-bill-grid-row-/);
        expect(rows[0]).toHaveTextContent(/25-0002/);
        expect(rows[0]).toHaveTextContent(/This bill/);
        expect(rows[1]).not.toHaveTextContent(/This bill/);
    });

    it("says no bills were processed when the run lists none", () => {
        render(<PerBillGridSection run={allBillsRun({ pipeline_run_bills: [] })} currentBillExternalId="" />);
        open();

        expect(screen.getByText("No bills processed yet")).toBeTruthy();
        expect(screen.getByText("Bill status will appear as the run progresses.")).toBeTruthy();
    });
});
