import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const mockRouterVisit = vi.fn<(...args: unknown[]) => void>();
const mockRouterPatch = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href, ...rest }: { children: React.ReactNode; href: string }) => (
        <a href={href} {...rest}>
            {children}
        </a>
    ),
    router: {
        visit: (...args: unknown[]) => mockRouterVisit(...args),
        patch: (...args: unknown[]) => mockRouterPatch(...args),
    },
    usePoll: vi.fn<(...args: unknown[]) => void>(),
}));

import Index, { type IBillSummaryReport } from "app/frontend/pages/admin/BillSummaryReports/Index";

const sampleReport: IBillSummaryReport = {
    id: 1,
    bill_id: 10,
    user_id: null,
    reason: "factual_inaccuracy",
    reason_label: "Factual inaccuracy",
    details: "The summary incorrectly states that fines are $500.",
    status: "pending",
    summary_snapshot: "This bill establishes a $500 fine for violations.",
    summary_ai_unreviewed: true,
    resolved_at: null,
    admin_notes: null,
    created_at: "2026-09-10T12:00:00Z",
    updated_at: "2026-09-10T12:00:00Z",
    reporter_display: "Guest (192.0.2.1)",
    bill_title: "Clean Water Ordinance",
    bill_external_id: "BILL-2026-001",
    bill_link: "https://example.com/bills/10",
    bill_current_summary: "This bill establishes a $500 fine for violations.",
    sway_locale_id: 1,
    sway_locale_name: "Baltimore City",
    resolved_by_name: null,
};

const mockCounts = {
    all: 1,
    pending: 1,
    reviewed: 0,
    resolved: 0,
    dismissed: 0,
};

const mockLocales = [
    { id: 1, name: "Baltimore City" },
    { id: 2, name: "Maryland" },
];

afterEach(() => {
    cleanup();
    vi.clearAllMocks();
});

describe("Admin BillSummaryReports Index", () => {
    it("renders page header, status tabs, and report cards", () => {
        render(
            <Index
                reports={[sampleReport]}
                status_counts={mockCounts}
                filter_status="pending"
                filter_locale_id={null}
                locales={mockLocales}
            />,
        );

        expect(screen.getByText("Bill Summary Reports")).toBeTruthy();
        expect(screen.getAllByText(/Clean Water Ordinance/).length).toBeGreaterThan(0);
        expect(screen.getAllByText(/BILL-2026-001/).length).toBeGreaterThan(0);
        expect(screen.getAllByText("The summary incorrectly states that fines are $500.").length).toBeGreaterThan(0);
        expect(screen.getAllByText("Guest (192.0.2.1)").length).toBeGreaterThan(0);
    });

    it("displays empty state message when no reports match", () => {
        render(
            <Index
                reports={[]}
                status_counts={{ all: 0, pending: 0, reviewed: 0, resolved: 0, dismissed: 0 }}
                filter_status="pending"
                filter_locale_id={null}
                locales={mockLocales}
            />,
        );

        expect(screen.getByText("No reports match the current filters.")).toBeTruthy();
    });

    it("clicking Resolve opens the resolution dialog", () => {
        render(
            <Index
                reports={[sampleReport]}
                status_counts={mockCounts}
                filter_status="pending"
                filter_locale_id={null}
                locales={mockLocales}
            />,
        );

        const resolveBtns = screen.getAllByTestId("btn-resolve-1");
        expect(resolveBtns.length).toBeGreaterThan(0);

        fireEvent.click(resolveBtns[0]);
        expect(screen.getByText("Mark Report as Resolved")).toBeTruthy();
    });

    it("submitting resolution triggers router.patch with resolved status", () => {
        render(
            <Index
                reports={[sampleReport]}
                status_counts={mockCounts}
                filter_status="pending"
                filter_locale_id={null}
                locales={mockLocales}
            />,
        );

        const resolveBtns = screen.getAllByTestId("btn-resolve-1");
        fireEvent.click(resolveBtns[0]);

        const confirmBtn = screen.getByTestId("btn-confirm-action");
        fireEvent.click(confirmBtn);

        expect(mockRouterPatch).toHaveBeenCalledWith(
            "/admin/bill_summary_reports/1",
            expect.objectContaining({
                bill_summary_report: expect.objectContaining({
                    status: "resolved",
                }),
            }),
            expect.anything(),
        );
    });
});
