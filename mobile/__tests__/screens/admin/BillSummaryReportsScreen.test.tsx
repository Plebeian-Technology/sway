import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import BillSummaryReportsScreen from "../../../src/screens/admin/BillSummaryReportsScreen";

const report = {
    id: 7,
    bill_id: 501,
    user_id: 12,
    reason: "inaccurate",
    details: "The summary says the bill passed.",
    status: "pending",
    summary_snapshot: "Snapshot",
    summary_ai_unreviewed: true,
    resolved_at: null,
    admin_notes: null,
    created_at: "2026-11-01T12:00:00Z",
    updated_at: "2026-11-01T12:00:00Z",
    reporter_display: "Ada L.",
    reason_label: "Inaccurate",
    bill_title: "Rent Stabilization",
    bill_external_id: "25-0042",
    bill_current_summary: "Current",
    bill_link: null,
    sway_locale_id: 5,
    sway_locale_name: "Baltimore, Maryland",
    resolved_by_name: null,
};

const page = (overrides: Record<string, unknown> = {}) => ({
    reports: [report],
    status_counts: { all: 9, pending: 4, reviewed: 2, resolved: 2, dismissed: 1 },
    locales: [
        { id: 5, name: "Baltimore, Maryland" },
        { id: 6, name: "Annapolis, Maryland" },
    ],
    filter_status: "all",
    filter_locale_id: null,
    ...overrides,
});

// @lat: [[mobile-admin-area#The bill summary reports screen]]
describe("BillSummaryReportsScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("shows each status with its count and a card for each report", async () => {
        mockApiGet.mockResolvedValue(page());
        render(<BillSummaryReportsScreen />);

        expect(await screen.findByText("25-0042: Rent Stabilization")).toBeTruthy();
        expect(screen.getByText("All (9)")).toBeTruthy();
        expect(screen.getByText("Pending (4)")).toBeTruthy();
        expect(screen.getByText("Reviewed (2)")).toBeTruthy();
        expect(screen.getByText("Resolved (2)")).toBeTruthy();
        expect(screen.getByText("Dismissed (1)")).toBeTruthy();
        expect(screen.getByText("Inaccurate")).toBeTruthy();
        expect(screen.getByText("The summary says the bill passed.")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_summary_reports?status=all", expect.anything());
    });

    it("refetches with the status query when a status is chosen", async () => {
        mockApiGet.mockResolvedValue(page());
        render(<BillSummaryReportsScreen />);
        await screen.findByText("Pending (4)");

        mockApiGet.mockResolvedValue(page({ filter_status: "resolved", reports: [] }));
        fireEvent.press(screen.getByText("Resolved (2)"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith(
                "/admin/bill_summary_reports?status=resolved",
                expect.anything(),
            ),
        );
        expect(await screen.findByText("No reports match the current filters.")).toBeTruthy();
    });

    it("refetches with the locale query when a locale is chosen and keeps the status", async () => {
        mockApiGet.mockResolvedValue(page());
        render(<BillSummaryReportsScreen />);
        await screen.findByText("Pending (4)");

        fireEvent.press(screen.getByText("Pending (4)"));
        fireEvent.press(screen.getByText("Annapolis, Maryland"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith(
                "/admin/bill_summary_reports?status=pending&locale_id=6",
                expect.anything(),
            ),
        );
    });

    it("makes each report card pressable", async () => {
        mockApiGet.mockResolvedValue(page());
        render(<BillSummaryReportsScreen />);

        const card = await screen.findByTestId("admin-bill-summary-report-7");
        expect(card.props.accessibilityRole).toBe("button");
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<BillSummaryReportsScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});
