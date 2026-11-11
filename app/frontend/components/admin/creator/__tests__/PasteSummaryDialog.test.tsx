// @lat: [[bill-paste-summary-response-outcomes#PasteSummaryDialog's test setup]]

import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerPost = vi.fn<(...args: unknown[]) => void>();
// The fake usePage below reads this object, letting a test change flash.paste_summary_errors
// between renders.
let mockPageProps: { flash?: { paste_summary_errors?: { path: string; message: string }[] } } = {};

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        reload: vi.fn<() => void>(),
    },
    usePage: () => ({ props: mockPageProps }),
}));

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

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
}));

vi.mock("app/frontend/components/ui/label", () => ({
    Label: ({ children, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) => (
        <label {...props}>{children}</label>
    ),
}));

vi.mock("app/frontend/components/ui/accordion", () => ({
    Accordion: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => <div {...props}>{children}</div>,
    AccordionItem: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    AccordionTrigger: ({ children }: { children: React.ReactNode }) => <button type="button">{children}</button>,
    AccordionContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

const notifyMock = vi.fn<(args: unknown) => void>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (args: unknown) => notifyMock(args),
}));

import PasteSummaryDialog from "app/frontend/components/admin/creator/PasteSummaryDialog";
import { PASTE_SUMMARY_SCHEMA_EXAMPLE } from "app/frontend/components/admin/creator/llm-summary/pasteSummarySchemaExample";

const SAMPLE_EXAMPLE = JSON.stringify(
    {
        summary_markdown: "Example summary.",
        draft_org_positions: [{ org_name: "ACME", stance: "support", summary: "We support this." }],
    },
    null,
    2,
);

afterEach(() => {
    cleanup();
    routerPost.mockReset();
    notifyMock.mockReset();
    mockPageProps = {};
});

describe("PasteSummaryDialog", () => {
    it("renders the Schema reference accordion + locked UI-SPEC copy", () => {
        render(<PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />);
        expect(screen.getByTestId("schema-reference-accordion")).toBeInTheDocument();
        expect(screen.getByText("Paste bill summary JSON")).toBeInTheDocument();
        expect(screen.getByText("Schema reference")).toBeInTheDocument();
        expect(screen.getByText("Copy example")).toBeInTheDocument();
        expect(screen.getByTestId("btn-validate-paste-summary").textContent).toBe("Validate & paste");
    });

    // Must not mention draft_org_positions — the server rejects pasted positions unless the bill
    // has testimony, so the old instruction just led to a refusal.
    it("does not instruct the operator to paste draft_org_positions", () => {
        render(<PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />);
        const textarea = screen.getByTestId("input-paste-summary-json");
        expect(textarea.getAttribute("placeholder")).not.toContain("draft_org_positions");
    });

    it("POSTs to /bills/:id/paste_summary with preserveScroll and NO errorBag/onError (REVIEW-10 MEDIUM-2)", () => {
        render(<PasteSummaryDialog billId={5} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />);
        fireEvent.change(screen.getByTestId("input-paste-summary-json"), {
            target: { value: '{"summary_markdown":"x","draft_org_positions":[]}' },
        });
        fireEvent.click(screen.getByTestId("btn-validate-paste-summary"));
        expect(routerPost).toHaveBeenCalledTimes(1);
        const [url, body, opts] = routerPost.mock.calls[0] as [
            string,
            { summary_json: string },
            { errorBag?: string; preserveScroll?: boolean; onError?: (errors: Record<string, string>) => void },
        ];
        expect(url).toBe("/bills/5/paste_summary");
        expect(body.summary_json).toBe('{"summary_markdown":"x","draft_org_positions":[]}');
        expect(opts.preserveScroll).toBe(true);
        // errorBag/onError must stay unset — rejections travel through flash[:paste_summary_errors],
        // not Inertia's shared errors prop.
        expect(opts.errorBag).toBeUndefined();
        expect(opts.onError).toBeUndefined();
    });

    // Validation errors live in flash[:paste_summary_errors], read via usePage().props.flash — not
    // Inertia's shared errors prop.
    it("renders flash.paste_summary_errors when no local submission errors exist", () => {
        mockPageProps = {
            flash: {
                paste_summary_errors: [
                    { path: "/draft_org_positions/0/stance", message: "must be one of: support, oppose, neutral" },
                    { path: "/summary_markdown", message: "is required" },
                ],
            },
        };
        render(<PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />);
        const list = screen.getByTestId("paste-summary-errors");
        expect(list).toBeInTheDocument();
        expect(list.textContent).toContain("/draft_org_positions/0/stance");
        expect(list.textContent).toContain("must be one of: support, oppose, neutral");
        expect(list.textContent).toContain("/summary_markdown");
        expect(list.textContent).toContain("is required");
    });

    // Inertia treats a redirect as success regardless of flash content — real success and
    // rejection both arrive via onSuccess.
    describe("onSuccess distinguishes a real success from a 302-with-flash-errors (C1-IN-03)", () => {
        const submit = (payload: string) => {
            const onOpenChange = vi.fn<(open: boolean) => void>();
            render(
                <PasteSummaryDialog
                    billId={9}
                    open={true}
                    onOpenChange={onOpenChange}
                    schemaExample={SAMPLE_EXAMPLE}
                />,
            );
            fireEvent.change(screen.getByTestId("input-paste-summary-json"), { target: { value: payload } });
            fireEvent.click(screen.getByTestId("btn-validate-paste-summary"));
            const opts = routerPost.mock.calls[0][2] as { onSuccess: (page: unknown) => void };
            return { onOpenChange, onSuccess: opts.onSuccess };
        };

        it("keeps the dialog open and the payload intact when the redirect carries validation errors", () => {
            const payload = '{"summary_markdown":""}';
            const { onOpenChange, onSuccess } = submit(payload);

            onSuccess({
                url: "/admin/bill_creator/9/summary",
                props: { flash: { paste_summary_errors: [{ path: "/summary_markdown", message: "is required" }] } },
            });

            expect(onOpenChange).not.toHaveBeenCalled();
            expect(screen.getByTestId("input-paste-summary-json")).toHaveValue(payload);
        });

        it("closes the dialog and clears the payload when the redirect carries none", () => {
            const { onOpenChange, onSuccess } = submit('{"summary_markdown":"ok"}');

            act(() => {
                onSuccess({ url: "/admin/bill_creator/9/summary", props: { flash: {} } });
            });

            expect(onOpenChange).toHaveBeenCalledWith(false);
            expect(screen.getByTestId("input-paste-summary-json")).toHaveValue("");
        });

        // A 200 with no flash slot at all is the same "nothing was rejected"
        // answer as an empty slot, and must not be read as a rejection.
        it("treats a response with no flash slot as a success", () => {
            const { onOpenChange, onSuccess } = submit('{"summary_markdown":"ok"}');

            act(() => {
                onSuccess({ url: "/admin/bill_creator/9/summary", props: {} });
            });

            expect(onOpenChange).toHaveBeenCalledWith(false);
        });

        // A lapsed admin session redirects to / with no paste_summary_errors — same shape as
        // success — so the dialog used to close and discard the paste unsaved.
        it("does not close the dialog, and says so, when the visit landed off the Bill Creator", () => {
            const { onOpenChange, onSuccess } = submit('{"summary_markdown":"ok"}');

            act(() => {
                onSuccess({ url: "/", props: { flash: {} } });
            });

            expect(onOpenChange).not.toHaveBeenCalled();
            expect(notifyMock).toHaveBeenCalledWith({
                level: "error",
                title: expect.stringMatching(/sign in as an admin/i),
            });
        });
    });

    it("Cancel clears textarea and invokes onOpenChange(false)", () => {
        const onOpenChange = vi.fn<(open: boolean) => void>();
        render(
            <PasteSummaryDialog billId={1} open={true} onOpenChange={onOpenChange} schemaExample={SAMPLE_EXAMPLE} />,
        );
        fireEvent.change(screen.getByTestId("input-paste-summary-json"), {
            target: { value: "{...}" },
        });
        // Two Cancel buttons would be ambiguous here; the dialog draws only one.
        fireEvent.click(screen.getByText("Cancel"));
        expect(onOpenChange).toHaveBeenCalledWith(false);
    });

    // The dialog must remember dismissed errors locally — the browser's flash copy persists on
    // page.props until a full reload, and the 5s poll never re-fetches flash.
    describe("a dismissed attempt's errors do not outlive its payload (C1-WR-05)", () => {
        const threeErrors = [
            { path: "/summary_markdown", message: "is required" },
            { path: "/categories", message: "must be an array" },
            { path: "/cited_section_keys/0", message: "must be a string" },
        ];

        const openWith = (errors: { path: string; message: string }[]) => {
            mockPageProps = { flash: { paste_summary_errors: errors } };
            return render(
                <PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />,
            );
        };

        it("drops them when the operator cancels and reopens", () => {
            const { rerender } = openWith(threeErrors);
            expect(screen.getByTestId("paste-summary-errors")).toBeInTheDocument();

            fireEvent.click(screen.getByText("Cancel"));
            rerender(
                <PasteSummaryDialog billId={1} open={false} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />,
            );
            rerender(
                <PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />,
            );

            expect(screen.queryByTestId("paste-summary-errors")).toBeNull();
            expect(screen.getByTestId("input-paste-summary-json")).toHaveValue("");
        });

        // @lat: [[paste-summary-dialog-dismissal-persistence#PasteSummaryDialog dismissal persistence]]
        it("stays dismissed when a poll's branch flip remounts the dialog at the other site", () => {
            const { unmount } = openWith(threeErrors);
            fireEvent.click(screen.getByText("Cancel"));
            unmount();

            // mockPageProps is left alone: the SAME flash array, because
            // nothing on this screen ever clears it.
            render(
                <PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />,
            );

            expect(screen.queryByTestId("paste-summary-errors")).toBeNull();
            expect(screen.getByTestId("input-paste-summary-json")).toHaveValue("");
        });

        // @lat: [[paste-summary-dialog-dismissal-persistence#PasteSummaryDialog dismissal persistence]]
        it("still renders a re-submission that fails in exactly the same way", () => {
            const { rerender } = openWith(threeErrors);
            fireEvent.click(screen.getByText("Cancel"));

            const sameFailuresFreshDelivery = threeErrors.map((error) => ({ ...error }));
            expect(sameFailuresFreshDelivery).toEqual(threeErrors);
            expect(sameFailuresFreshDelivery).not.toBe(threeErrors);

            mockPageProps = { flash: { paste_summary_errors: sameFailuresFreshDelivery } };
            rerender(
                <PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />,
            );

            const rendered = screen.getByTestId("paste-summary-errors").textContent;
            expect(rendered).toContain("is required");
            expect(rendered).toContain("must be an array");
            expect(rendered).toContain("must be a string");
        });
    });

    it("click-to-jump: clicking an error focuses the textarea and positions the cursor at the resolved JSONPointer offset", () => {
        mockPageProps = {
            flash: {
                paste_summary_errors: [{ path: "/summary_markdown", message: "is required" }],
            },
        };
        render(<PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />);
        const textarea = screen.getByTestId("input-paste-summary-json") as HTMLTextAreaElement;
        const payload = '{"summary_markdown":"hi","draft_org_positions":[]}';
        fireEvent.change(textarea, { target: { value: payload } });

        const errorButton = screen.getByTestId("paste-summary-error-0");
        fireEvent.click(errorButton);

        expect(document.activeElement).toBe(textarea);
        // Offset of `"summary_markdown"` inside the payload is index 1
        // (just past the opening brace).
        const expected = payload.indexOf('"summary_markdown"');
        expect(textarea.selectionStart).toBe(expected);
        expect(textarea.selectionEnd).toBe(expected);
    });

    it("includes news_usage and source_uses in the schema example", () => {
        expect(PASTE_SUMMARY_SCHEMA_EXAMPLE).toContain('"news_usage"');
        expect(PASTE_SUMMARY_SCHEMA_EXAMPLE).toContain('"source_uses"');
    });

    it("clarifies that pasting creates a review draft rather than publishing immediately", () => {
        render(<PasteSummaryDialog billId={1} open={true} onOpenChange={() => {}} schemaExample={SAMPLE_EXAMPLE} />);
        expect(screen.getByText(/create a review draft/i)).toBeInTheDocument();
    });
});
