import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockPost = vi.fn<(...args: unknown[]) => void>();
let mockFormData = {
    reason: "",
    details: "",
};
let mockProcessing = false;
let mockErrors: Record<string, string> | undefined = {};
let mockPageProps: Record<string, unknown> = {
    user: null,
};

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({
        props: mockPageProps,
    }),
    useForm: () => ({
        data: mockFormData,
        setData: vi.fn<(key: string, value: unknown) => void>((key: string, value: unknown) => {
            if (typeof key === "string") {
                mockFormData = { ...mockFormData, [key]: value };
            }
        }),
        post: mockPost,
        reset: vi.fn<() => void>(),
        processing: mockProcessing,
        errors: mockErrors,
    }),
}));

import ReportSummaryDialog from "app/frontend/components/bill/ReportSummaryDialog";

beforeEach(() => {
    localStorage.clear();
    mockFormData = { reason: "", details: "" };
    mockProcessing = false;
    mockErrors = {};
    mockPageProps = { user: null };
    mockPost.mockClear();
});

afterEach(() => {
    cleanup();
});

describe("ReportSummaryDialog", () => {
    it("renders dialog content when open", () => {
        render(
            <ReportSummaryDialog
                open={true}
                onOpenChange={vi.fn<(open: boolean) => void>()}
                billId={42}
                billLink="https://example.com/bill"
            />,
        );

        expect(screen.getByTestId("report-summary-form")).toBeTruthy();
        expect(screen.getByText("Report Inaccurate Summary")).toBeTruthy();
        expect(screen.getByText("Factual inaccuracy")).toBeTruthy();
        expect(screen.getByText("Misleading tone or bias")).toBeTruthy();
        expect(screen.getByText("Missing amendment or outdated text")).toBeTruthy();
        expect(screen.getByText("Other issue")).toBeTruthy();
        expect(screen.getByText(/Submitting as guest/)).toBeTruthy();
    });

    it("disables submit button when form is invalid (empty reason and short details)", () => {
        mockFormData = { reason: "", details: "short" };
        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        const submitButton = screen.getByTestId("btn-submit-report");
        expect(submitButton).toBeDisabled();
    });

    it("enables submit button when reason is chosen and details >= 10 characters", () => {
        mockFormData = { reason: "factual_inaccuracy", details: "This summary claims section 4 bans dogs." };
        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        const submitButton = screen.getByTestId("btn-submit-report");
        expect(submitButton).not.toBeDisabled();
    });

    it("calls form.post on submission with correct url and options", () => {
        mockFormData = { reason: "factual_inaccuracy", details: "This summary claims section 4 bans dogs." };
        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        const form = screen.getByTestId("report-summary-form");
        fireEvent.submit(form);

        expect(mockPost).toHaveBeenCalledWith(
            "/bills/42/summary_reports",
            expect.objectContaining({
                preserveScroll: true,
                onSuccess: expect.any(Function),
            }),
        );
    });

    it("shows confirmation view if localStorage indicates already reported", () => {
        localStorage.setItem("sway:reported_bill_42", "true");

        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        expect(screen.getByTestId("report-confirmation-view")).toBeTruthy();
        expect(screen.getByText(/already submitted a report/i)).toBeTruthy();
    });

    it("transitions to confirmation view and sets localStorage on successful submission", () => {
        mockFormData = { reason: "factual_inaccuracy", details: "This summary claims section 4 bans dogs." };
        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        const form = screen.getByTestId("report-summary-form");
        fireEvent.submit(form);

        expect(mockPost).toHaveBeenCalled();
        const postOptions = mockPost.mock.calls[0][1] as { onSuccess?: () => void };
        expect(postOptions.onSuccess).toBeDefined();

        // Trigger the onSuccess callback inside act()
        act(() => {
            postOptions.onSuccess?.();
        });

        expect(localStorage.getItem("sway:reported_bill_42")).toBe("true");
    });

    it("renders authenticated state without guest notice when user is present", () => {
        mockPageProps = { user: { id: 1, email: "user@example.com" } };

        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        expect(screen.queryByText(/Submitting as guest/)).toBeNull();
    });

    it("renders validation errors when form.errors contains reason and details", () => {
        mockErrors = {
            reason: "Please select a valid reason",
            details: "Details must be at least 10 characters",
        };

        render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);

        expect(screen.getByText("Please select a valid reason")).toBeTruthy();
        expect(screen.getByText("Details must be at least 10 characters")).toBeTruthy();
    });

    it("mounts safely without throwing when form.errors is undefined", () => {
        mockErrors = undefined;

        expect(() => {
            render(<ReportSummaryDialog open={true} onOpenChange={vi.fn<(open: boolean) => void>()} billId={42} />);
        }).not.toThrow();

        expect(screen.getByTestId("report-summary-form")).toBeTruthy();
    });
});
