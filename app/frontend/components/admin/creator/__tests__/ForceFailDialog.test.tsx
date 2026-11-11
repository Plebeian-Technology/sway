import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerPost = vi.fn<(...args: unknown[]) => void>();
const notifyMock = vi.fn<(args: unknown) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
    },
}));

vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return { ...actual, notify: (args: unknown) => notifyMock(args) };
});

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, disabled, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} disabled={disabled} {...props}>
            {children}
        </button>
    ),
}));

vi.mock("app/frontend/components/ui/dialog", () => ({
    Dialog: ({ children, open }: { children: React.ReactNode; open?: boolean }) =>
        open ? <div data-testid="dialog">{children}</div> : null,
    DialogContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogDescription: ({ children }: { children: React.ReactNode }) => <p>{children}</p>,
    DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogTitle: ({ children }: { children: React.ReactNode }) => <h3>{children}</h3>,
}));

vi.mock("app/frontend/components/ui/input", () => ({
    Input: (props: React.InputHTMLAttributes<HTMLInputElement>) => <input {...props} />,
}));

vi.mock("app/frontend/components/ui/label", () => ({
    Label: ({ children, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) => (
        <label {...props}>{children}</label>
    ),
}));

import ForceFailDialog from "app/frontend/components/admin/creator/ForceFailDialog";

afterEach(() => {
    cleanup();
    routerPost.mockReset();
    notifyMock.mockReset();
});

describe("ForceFailDialog", () => {
    it("Confirm is disabled until phrase exactly matches 'force fail'", () => {
        render(<ForceFailDialog runId={1} open={true} onOpenChange={() => {}} />);
        const confirm = screen.getByTestId("btn-force-fail-confirm");
        expect(confirm).toBeDisabled();

        const input = screen.getByTestId("input-force-fail-confirm");
        fireEvent.change(input, { target: { value: "force fai" } });
        expect(confirm).toBeDisabled();

        fireEvent.change(input, { target: { value: "Force Fail" } });
        expect(confirm).toBeDisabled();

        fireEvent.change(input, { target: { value: "force fail" } });
        expect(confirm).not.toBeDisabled();
    });

    it("Confirm POSTs to /pipeline_runs/:id/force_fail with confirm_phrase=force fail and preserveScroll", () => {
        render(<ForceFailDialog runId={42} open={true} onOpenChange={() => {}} />);
        fireEvent.change(screen.getByTestId("input-force-fail-confirm"), {
            target: { value: "force fail" },
        });
        fireEvent.click(screen.getByTestId("btn-force-fail-confirm"));
        expect(routerPost).toHaveBeenCalledWith(
            "/pipeline_runs/42/force_fail",
            { confirm_phrase: "force fail", back_to: "bill_creator" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("Cancel clears the input and calls onOpenChange(false)", () => {
        const onOpenChange = vi.fn<(open: boolean) => void>();
        render(<ForceFailDialog runId={1} open={true} onOpenChange={onOpenChange} />);
        fireEvent.change(screen.getByTestId("input-force-fail-confirm"), {
            target: { value: "force fail" },
        });
        const cancelBtn = screen.getByText("Cancel");
        fireEvent.click(cancelBtn);
        expect(onOpenChange).toHaveBeenCalledWith(false);
    });

    // @lat: [[toasts#Toasts#Flash toast dedupe#A refusal that arrives in the errors hash needs its own reader]]
    it("toasts the server's refusal copy when force-fail is refused", () => {
        render(<ForceFailDialog runId={42} open={true} onOpenChange={() => {}} />);
        fireEvent.change(screen.getByTestId("input-force-fail-confirm"), {
            target: { value: "force fail" },
        });
        fireEvent.click(screen.getByTestId("btn-force-fail-confirm"));

        const options = routerPost.mock.calls[0][2] as Record<string, unknown>;
        const onError = options.onError as (errors: unknown) => void;
        expect(typeof onError).toBe("function");

        onError({ pipeline: "Run #42 is not in-flight (status: succeeded)" });
        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: "Run #42 is not in-flight (status: succeeded)",
        });

        notifyMock.mockClear();
        onError({});
        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: "Could not force-fail this run.",
        });
    });

    it("renders the locked UI-SPEC copy verbatim", () => {
        render(<ForceFailDialog runId={1} open={true} onOpenChange={() => {}} />);
        expect(screen.getByText("Force-fail this run?")).toBeInTheDocument();
        // the description has a bold part inside it, so check both pieces are there
        expect(screen.getByText(/This will immediately mark the run as failed/)).toBeInTheDocument();
        // Two buttons carry the label "Force fail". The one that opens the dialog
        // lives in the parent; this dialog only draws the confirm button.
        expect(screen.getByTestId("btn-force-fail-confirm").textContent).toBe("Force fail");
    });
});
