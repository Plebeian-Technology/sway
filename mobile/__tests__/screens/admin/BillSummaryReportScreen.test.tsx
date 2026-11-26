import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
const mockApiPatch = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
    },
}));

jest.mock("../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import BillSummaryReportScreen from "../../../src/screens/admin/BillSummaryReportScreen";

const report = {
    id: 7,
    bill_id: 501,
    user_id: 12,
    reason: "inaccurate",
    details: "The summary says the bill passed.",
    status: "pending",
    summary_snapshot: "Snapshot of the summary the reader saw",
    summary_ai_unreviewed: true,
    resolved_at: null,
    admin_notes: "Checking the vote record",
    created_at: "2026-11-01T12:00:00Z",
    updated_at: "2026-11-01T12:00:00Z",
    reporter_display: "Ada L.",
    reason_label: "Inaccurate",
    bill_title: "Rent Stabilization",
    bill_external_id: "25-0042",
    bill_current_summary: "Current summary of the bill",
    bill_link: null,
    sway_locale_id: 5,
    sway_locale_name: "Baltimore, Maryland",
    resolved_by_name: null,
};

const route = { key: "r", name: "AdminBillSummaryReport" as const, params: { id: 7 } };

// @lat: [[mobile-admin-area#The bill summary report screen]]
describe("BillSummaryReportScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue(report);
    });

    it("renders the report fetched by id", async () => {
        render(<BillSummaryReportScreen route={route} />);

        expect(await screen.findByText("25-0042: Rent Stabilization")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_summary_reports/7", expect.anything());
        expect(screen.getByText("Baltimore, Maryland")).toBeTruthy();
        expect(screen.getByText("Inaccurate")).toBeTruthy();
        expect(screen.getByText("The summary says the bill passed.")).toBeTruthy();
        expect(screen.getByText("Snapshot of the summary the reader saw")).toBeTruthy();
        expect(screen.getByText("Current summary of the bill")).toBeTruthy();
        expect(screen.getByTestId("admin-bill-summary-report-notes-input").props.value).toBe(
            "Checking the vote record",
        );
        expect(screen.getByTestId("admin-bill-summary-report-status-pending").props.accessibilityState.selected).toBe(
            true,
        );
    });

    it("saves the chosen status and notes with PATCH bill_summary_report", async () => {
        mockApiPatch.mockResolvedValue({ ...report, status: "resolved", admin_notes: "Fixed in the summary" });
        render(<BillSummaryReportScreen route={route} />);
        await screen.findByText("25-0042: Rent Stabilization");

        fireEvent.press(screen.getByTestId("admin-bill-summary-report-status-resolved"));
        fireEvent.changeText(screen.getByTestId("admin-bill-summary-report-notes-input"), "Fixed in the summary");
        fireEvent.press(screen.getByTestId("admin-bill-summary-report-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/bill_summary_reports/7", {
                bill_summary_report: { status: "resolved", admin_notes: "Fixed in the summary" },
            }),
        );
        expect(await screen.findByText("Saved.")).toBeTruthy();
    });

    it("shows the server's message when the save is rejected with a 422", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError("validation_failed", "Admin notes is too long", undefined, 422),
        );
        render(<BillSummaryReportScreen route={route} />);
        await screen.findByText("25-0042: Rent Stabilization");

        fireEvent.press(screen.getByTestId("admin-bill-summary-report-save"));

        expect(await screen.findByText("Admin notes is too long")).toBeTruthy();
        expect(screen.queryByText("Saved.")).toBeNull();
    });

    it("shows the server's message when the report cannot be loaded", async () => {
        mockApiGet.mockRejectedValue(new ApiRequestError("not_found", "Report not found.", undefined, 404));
        render(<BillSummaryReportScreen route={route} />);

        expect(await screen.findByText("Report not found.")).toBeTruthy();
    });
});
