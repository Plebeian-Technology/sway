import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import TestimonyAcknowledgeButton from "app/frontend/components/admin/creator/testimony-report/TestimonyAcknowledgeButton";
import { ITestimonyCoverage } from "app/frontend/components/admin/creator/llm-summary/types";

const routerPost = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
    },
}));

const notify = vi.fn<(...args: unknown[]) => void>();

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notify(...args),
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, disabled, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} disabled={disabled} {...props}>
            {children}
        </button>
    ),
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, ...props }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string; tone?: string }) => (
        <span {...props}>{children}</span>
    ),
}));

const baseCoverage: ITestimonyCoverage = {
    state: "cleaned",
    coverage_gap: true,
    total_chars: 1_000,
    reached_chars: 900,
    removed_chars: 0,
    repair_added_chars: 0,
    left_out_chars: 100,
    total_letters: 5,
    reached_letters: 4,
    removed_letters: 0,
    left_out_letters: 1,
    individual_letter_count: 0,
    model_fallback_letter_count: 0,
    attachment_cut_count: 0,
    attachment_cut_cap: null,
    paste_present: false,
    paste_chars: 0,
    paste_share_of_limit: null,
    displaced_letter_count: 0,
    digest: "abc123",
    acknowledged: false,
    acknowledged_by_email: null,
    acknowledged_at: null,
};

afterEach(() => {
    routerPost.mockReset();
    notify.mockReset();
});

describe("TestimonyAcknowledgeButton", () => {
    it("renders the fixed-copy button when the coverage is not acknowledged", () => {
        render(<TestimonyAcknowledgeButton billId={42} coverage={baseCoverage} runInFlight={false} />);

        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeInTheDocument();
    });

    it("posts the bill's digest to the acknowledgement endpoint on click", () => {
        render(<TestimonyAcknowledgeButton billId={42} coverage={baseCoverage} runInFlight={false} />);

        fireEvent.click(screen.getByRole("button", { name: "Acknowledge the missing testimony" }));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/testimony_coverage_acknowledgement",
            { digest: "abc123" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("disables the button between the click and the server's answer", () => {
        render(<TestimonyAcknowledgeButton billId={42} coverage={baseCoverage} runInFlight={false} />);

        const button = screen.getByRole("button", { name: "Acknowledge the missing testimony" });
        fireEvent.click(button);

        expect(button).toBeDisabled();
    });

    it("is disabled while a pipeline run is in flight", () => {
        render(<TestimonyAcknowledgeButton billId={42} coverage={baseCoverage} runInFlight={true} />);

        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeDisabled();
    });

    it("routes a refusal through notifyServerRefusal under the testimony_coverage key", () => {
        render(<TestimonyAcknowledgeButton billId={42} coverage={baseCoverage} runInFlight={false} />);

        fireEvent.click(screen.getByRole("button", { name: "Acknowledge the missing testimony" }));

        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        expect(typeof opts.onError).toBe("function");
        opts.onError?.({ testimony_coverage: "The testimony coverage numbers changed since this page loaded." });

        expect(notify).toHaveBeenCalledWith(
            expect.objectContaining({
                level: "error",
                title: "The testimony coverage numbers changed since this page loaded.",
            }),
        );
    });

    it("renders the ACKNOWLEDGED stamp and the acknowledged-by line once the server says so, not the button", () => {
        const acknowledged: ITestimonyCoverage = {
            ...baseCoverage,
            acknowledged: true,
            acknowledged_by_email: "github@sway.vote",
            acknowledged_at: "2026-08-13T20:51:00Z",
        };

        render(<TestimonyAcknowledgeButton billId={42} coverage={acknowledged} runInFlight={false} />);

        expect(screen.getByText("ACKNOWLEDGED")).toBeInTheDocument();
        expect(screen.getByText(/Acknowledged by github@sway\.vote on/)).toBeInTheDocument();
        expect(screen.queryByRole("button", { name: "Acknowledge the missing testimony" })).toBeNull();
    });
});
