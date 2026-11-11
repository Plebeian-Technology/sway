// @lat: [[llm-summary-empty-state-test-notes#Why this file pins the no-draft_org_positions wording]]

import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const notifyMock = vi.fn<(args: unknown) => void>();
vi.mock("app/frontend/sway_utils", () => ({ notify: (args: unknown) => notifyMock(args) }));
import LlmSummaryEmptyState from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEmptyState";

// @lat: [[llm-summary-empty-state-test-notes#Fake router/page shapes are load-bearing]]
type TServedPage = {
    // @lat: [[llm-summary-empty-state-test-notes#Fake router/page shapes are load-bearing]]
    url: string;
    props: {
        flash: Record<string, unknown>;
        bill?: { bill_pipeline_refresh?: { status: "queued" | "running" | "completed" | null } | null };
    };
};
type TVisitOptions = { only?: string[]; onSuccess?: (page: TServedPage) => void };

const SERVED_PROMPT = "## Bill metadata\n- External ID: CB-23-0312";

// @lat: [[llm-summary-empty-state-test-notes#Fake router/page shapes are load-bearing]]
const LANDED_URL = "/admin/bill_creator/7/summary";

const routerPost = vi.fn<(_url: string, _data: unknown, options: TVisitOptions) => void>(
    (_url: string, _data: unknown, options: TVisitOptions) => {
        options.onSuccess?.({ url: LANDED_URL, props: { flash: {} } });
    },
);

// @lat: [[llm-summary-empty-state-test-notes#Why summary_prompt is asserted as a fresh top-level prop]]
const routerReload = vi.fn<(options: TVisitOptions) => void>((options: TVisitOptions) => {
    options.onSuccess?.({ url: LANDED_URL, props: { flash: {} } });
});

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (url: string, data: unknown, options: TVisitOptions) => routerPost(url, data, options),
        reload: (options: TVisitOptions) => routerReload(options),
    },
    // @lat: [[llm-summary-empty-state-test-notes#Component scope notes]]
    usePage: () => ({ props: {} }),
    // @lat: [[llm-summary-empty-state-test-notes#Component scope notes]]
    Link: ({ href, children, ...props }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
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
    DialogContent: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => <div {...props}>{children}</div>,
    DialogDescription: ({ children }: { children: React.ReactNode }) => <p>{children}</p>,
    DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogTitle: ({ children }: { children: React.ReactNode }) => <h3>{children}</h3>,
}));

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
}));

vi.mock("app/frontend/components/ui/alert", () => ({
    Alert: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => <div {...props}>{children}</div>,
    AlertDescription: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    AlertTitle: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

const baseProps = {
    billId: 7,
    externalId: "CB-23-0312",
    summaryPrompt: SERVED_PROMPT,
    billPipelineStatus: null,
    billPipelineFailure: null,
    isBillPipelineRunning: false,
};

beforeEach(() => {
    routerPost.mockClear();
    routerReload.mockClear();
    notifyMock.mockClear();
});

// @lat: [[llm-summary-empty-state-test-notes#The pipeline-failure alert]]
describe("the pipeline failure alert", () => {
    it("shows the reason the last run failed", () => {
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                billPipelineFailure={{
                    run_id: 77,
                    error_message: "fetch_hearings: matter 9928 not found",
                    failed_at: "2026-08-01T00:00:00Z",
                }}
            />,
        );

        const alert = screen.getByTestId("bill-pipeline-error-alert");
        expect(alert).toHaveTextContent("fetch_hearings: matter 9928 not found");
        expect(alert).toHaveTextContent("CB-23-0312");
        // @lat: [[llm-summary-empty-state-test-notes#The pipeline-failure alert]]
        expect(alert.textContent ?? "").not.toMatch(/solid queue|job logs/i);
        expect(alert).toHaveTextContent(/pipeline tab/i);
    });

    // @lat: [[llm-summary-empty-state-test-notes#The pipeline-failure alert]]
    it("links to the failed run itself, not just to the tab", () => {
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                billPipelineFailure={{
                    run_id: 77,
                    error_message: "fetch_hearings: matter 9928 not found",
                    failed_at: "2026-08-01T00:00:00Z",
                }}
            />,
        );

        const link = screen.getByTestId("link-failed-run-on-pipeline-tab");
        expect(link).toHaveAttribute("href", "/admin/bill_creator/7/pipeline?run_id=77");
    });

    it("stays away when no run has failed", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);

        expect(screen.queryByTestId("bill-pipeline-error-alert")).toBeNull();
    });

    // @lat: [[llm-summary-empty-state-test-notes#The pipeline-failure alert]]
    it("stays away while a run is going", () => {
        render(<LlmSummaryEmptyState {...baseProps} billPipelineStatus="running" isBillPipelineRunning={true} />);

        expect(screen.queryByTestId("bill-pipeline-error-alert")).toBeNull();
    });
});

const openPromptDialog = () => {
    render(<LlmSummaryEmptyState {...baseProps} />);
    fireEvent.click(screen.getByTestId("btn-prepare-prompt"));
    return screen.getByTestId("prompt-dialog");
};

describe("LlmSummaryEmptyState — Prepare-prompt dialog copy (B4-CR-01)", () => {
    it("opens the dialog with the served prompt", () => {
        const dialog = openPromptDialog();

        expect(dialog).toBeInTheDocument();
        expect(screen.getByTestId("textarea-summary-prompt")).toHaveValue(baseProps.summaryPrompt);
    });

    // @lat: [[llm-summary-empty-state-test-notes#handlePreparePrompt: a reload, not a POST]]
    it("asks for the summary_prompt prop by name rather than posting", () => {
        render(<LlmSummaryEmptyState {...baseProps} summaryPrompt={null} />);

        fireEvent.click(screen.getByTestId("btn-prepare-prompt"));

        expect(routerReload).toHaveBeenCalledTimes(1);
        expect(routerPost).not.toHaveBeenCalled();
        expect(routerReload.mock.calls[0][0]).toMatchObject({
            only: ["summary_prompt", "bill"],
        });
    });

    // @lat: [[llm-summary-empty-state-test-notes#handlePreparePrompt: a reload, not a POST]]
    it("shows the prompt the reload delivers, not the one it had at first render", () => {
        const { rerender } = render(<LlmSummaryEmptyState {...baseProps} summaryPrompt={null} />);
        fireEvent.click(screen.getByTestId("btn-prepare-prompt"));
        expect(screen.getByTestId("textarea-summary-prompt")).toHaveValue("");

        // @lat: [[llm-summary-empty-state-test-notes#handlePreparePrompt: a reload, not a POST]]
        rerender(<LlmSummaryEmptyState {...baseProps} summaryPrompt={SERVED_PROMPT} />);

        expect(screen.getByTestId("textarea-summary-prompt")).toHaveValue(SERVED_PROMPT);
    });

    // @lat: [[llm-summary-empty-state-test-notes#Prompt staleness]]
    describe("when the pipeline moves under a prepared prompt", () => {
        const prepareUnder = (status: "queued" | "running" | "completed" | null) => {
            routerReload.mockImplementationOnce((options: TVisitOptions) => {
                options.onSuccess?.({
                    url: LANDED_URL,
                    props: { flash: {}, bill: { bill_pipeline_refresh: { status } } },
                });
            });
            const view = render(<LlmSummaryEmptyState {...baseProps} billPipelineStatus={status} />);
            fireEvent.click(screen.getByTestId("btn-prepare-prompt"));
            return view;
        };

        it("says the prompt is out of date once the status changes", () => {
            const { rerender } = prepareUnder("running");
            expect(screen.queryByTestId("prompt-dialog-stale")).toBeNull();

            rerender(<LlmSummaryEmptyState {...baseProps} billPipelineStatus="completed" />);

            expect(screen.getByTestId("prompt-dialog-stale")).toBeInTheDocument();
        });

        // @lat: [[llm-summary-empty-state-test-notes#Prompt staleness]]
        it("refuses to copy it, and says why", async () => {
            const { rerender } = prepareUnder("running");
            rerender(<LlmSummaryEmptyState {...baseProps} billPipelineStatus="completed" />);

            expect(screen.getByTestId("btn-copy-prompt")).toBeDisabled();

            fireEvent.click(screen.getByTestId("btn-copy-prompt"));
            await waitFor(() =>
                expect(notifyMock).not.toHaveBeenCalledWith(expect.objectContaining({ level: "success" })),
            );
        });

        // @lat: [[llm-summary-empty-state-test-notes#Prompt staleness]]
        it("offers Prepare again in the dialog", () => {
            const { rerender } = prepareUnder("running");
            rerender(<LlmSummaryEmptyState {...baseProps} billPipelineStatus="completed" />);

            expect(screen.getByTestId("btn-reprepare-prompt")).toBeInTheDocument();
        });

        // @lat: [[llm-summary-empty-state-test-notes#Prompt staleness]]
        it("stays quiet while the pipeline has not moved", () => {
            const { rerender } = prepareUnder("completed");

            rerender(<LlmSummaryEmptyState {...baseProps} billPipelineStatus="completed" />);

            expect(screen.queryByTestId("prompt-dialog-stale")).toBeNull();
            expect(screen.getByTestId("btn-copy-prompt")).not.toBeDisabled();
        });
    });

    // @lat: [[llm-summary-empty-state-test-notes#handleCopyPrompt: never fail in silence]]
    it("says so when there is no prompt to copy, instead of doing nothing", async () => {
        render(<LlmSummaryEmptyState {...baseProps} summaryPrompt={null} />);
        fireEvent.click(screen.getByTestId("btn-prepare-prompt"));

        fireEvent.click(screen.getByTestId("btn-copy-prompt"));
        await waitFor(() => expect(notifyMock).toHaveBeenCalled());

        expect(notifyMock).toHaveBeenCalledWith(expect.objectContaining({ level: "error" }));
    });

    // @lat: [[llm-summary-empty-state-test-notes#Why this file pins the no-draft_org_positions wording]]
    it("does not instruct the operator to have the agent return draft_org_positions", () => {
        const dialog = openPromptDialog();

        expect(dialog.textContent).not.toContain("draft_org_positions");
        expect(dialog.textContent).not.toContain("org_position");
    });
});

// @lat: [[llm-summary-empty-state-test-notes#The dialog's schema-key wording bug]]
describe("LlmSummaryEmptyState — Prepare-prompt dialog matches the schema (B4-IN-05)", () => {
    it("names the keys config/schemas/bill_summary.json actually accepts", () => {
        const dialog = openPromptDialog();

        expect(dialog.textContent).toContain("summary_markdown");
        expect(dialog.textContent).toContain("full_breakdown_markdown");
    });

    it("does not name the persisted column names the schema rejects", () => {
        const dialog = openPromptDialog();

        expect(dialog.textContent).not.toContain("llm_summary");
        expect(dialog.textContent).not.toContain("llm_full_breakdown");
    });

    // @lat: [[llm-summary-empty-state-test-notes#LlmSummaryPasteFallback]]
    it("names the paste control that is actually on this screen", () => {
        const dialog = openPromptDialog();

        expect(dialog.textContent).toMatch(/Paste summary JSON/);
        expect(screen.getByTestId("btn-paste-summary-fallback").textContent).toBe("Paste summary JSON");
    });

    it("does not tell the operator there is nowhere to paste, or to generate first", () => {
        openPromptDialog();
        const copy = screen.getByTestId("prompt-dialog-paste-destination").textContent ?? "";

        // @lat: [[llm-summary-empty-state-test-notes#LlmSummaryPasteFallback]]
        expect(copy).toBeTruthy();
        expect(copy).not.toMatch(/no place to paste|not on this screen|nowhere/i);
        expect(copy).not.toMatch(/Generate summary/);
    });
});

// @lat: [[llm-summary-empty-state-test-notes#Generate button busy wording]]
describe("LlmSummaryEmptyState — a disabled Generate always says why (C1-IN-02)", () => {
    const queued = {
        ...baseProps,
        billPipelineStatus: "queued" as const,
        isBillPipelineRunning: true,
    };

    it("disables Generate while the pipeline is queued", () => {
        render(<LlmSummaryEmptyState {...queued} />);

        expect(screen.getByTestId("btn-generate-summary-empty-state")).toBeDisabled();
    });

    it("explains the queued state on screen instead of leaving a dead button", () => {
        render(<LlmSummaryEmptyState {...queued} />);

        expect(screen.getByTestId("bill-pipeline-refresh-status")).toBeInTheDocument();
    });

    it("still explains the running state", () => {
        render(<LlmSummaryEmptyState {...baseProps} billPipelineStatus="running" isBillPipelineRunning={true} />);

        expect(screen.getByTestId("bill-pipeline-refresh-status")).toBeInTheDocument();
    });

    it("shows no pipeline explanation when nothing is in flight", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);

        expect(screen.queryByTestId("bill-pipeline-refresh-status")).toBeNull();
        expect(screen.getByTestId("btn-generate-summary-empty-state")).not.toBeDisabled();
    });

    // @lat: [[llm-summary-empty-state-test-notes#Generate button busy wording]]
    it("points the disabled Generate at the notice that explains it", () => {
        render(<LlmSummaryEmptyState {...queued} />);

        const notice = screen.getByTestId("bill-pipeline-refresh-status");
        expect(notice.id).toBe("bill-pipeline-busy-notice");
        expect(screen.getByTestId("btn-generate-summary-empty-state")).toHaveAttribute("aria-describedby", notice.id);
    });

    it("says nothing about a pipeline that is not running", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);

        expect(screen.getByTestId("btn-generate-summary-empty-state")).not.toHaveAttribute("aria-describedby");
    });
});

// @lat: [[llm-summary-empty-state-test-notes#LlmSummaryPasteFallback]]
describe("LlmSummaryEmptyState paste affordance", () => {
    it("offers a paste destination alongside the prompt it hands out", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);

        expect(screen.getByTestId("btn-prepare-prompt")).toBeInTheDocument();
        expect(screen.getByTestId("btn-paste-summary-fallback")).toBeInTheDocument();
    });

    it("opens the paste dialog when the affordance is clicked", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);

        fireEvent.click(screen.getByTestId("btn-paste-summary-fallback"));

        expect(screen.getByTestId("paste-summary-dialog")).toBeInTheDocument();
    });

    // @lat: [[llm-summary-empty-state-test-notes#Regression: onSuccess called with no argument]]
    it("submits the pasted payload to this bill's paste_summary endpoint", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);
        fireEvent.click(screen.getByTestId("btn-paste-summary-fallback"));

        fireEvent.change(screen.getByTestId("input-paste-summary-json"), {
            target: { value: '{"summary_markdown":"pasted from the external agent"}' },
        });
        fireEvent.click(screen.getByTestId("btn-validate-paste-summary"));

        const pasteCall = routerPost.mock.calls.find((c) => String(c[0]).endsWith("/paste_summary"));
        expect(pasteCall?.[0]).toBe("/bills/7/paste_summary");
    });

    // @lat: [[llm-summary-empty-state-test-notes#The full round trip this screen promises]]
    it("closes the dialog on a clean paste without spending a generation", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);
        fireEvent.click(screen.getByTestId("btn-paste-summary-fallback"));

        fireEvent.change(screen.getByTestId("input-paste-summary-json"), {
            target: { value: '{"summary_markdown":"pasted from the external agent"}' },
        });
        fireEvent.click(screen.getByTestId("btn-validate-paste-summary"));

        expect(screen.queryByTestId("paste-summary-dialog")).toBeNull();
        expect(routerPost.mock.calls.some((c) => String(c[0]).endsWith("/regenerate_summary"))).toBe(false);
    });
});

// A bill nobody has summarised is where a stronger model is most often wanted,
// and this branch had no picker and sent no model at all.
describe("the per-run model on the empty state's Generate summary", () => {
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    const options = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5" },
        { id: "claude-opus-5-5", label: "Opus 5.5" },
    ];

    it("offers the picker the server's models", () => {
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                modelOptions={options}
                selectedModel="claude-opus-5-5"
                onModelChange={vi.fn<(model: string) => void>()}
            />,
        );

        expect(screen.getByTestId("select-summary-model").textContent).toContain("Opus 5.5");
    });

    it("carries the chosen model with the request", () => {
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                modelOptions={options}
                selectedModel="claude-opus-5-5"
                onModelChange={vi.fn<(model: string) => void>()}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });

    it("sends no model key, and renders no picker, when the server offered none", () => {
        render(<LlmSummaryEmptyState {...baseProps} />);

        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(screen.queryByTestId("select-summary-model")).toBeNull();
        expect(routerPost.mock.calls[0][1]).toEqual({});
    });

    it("omits reasoning_effort when the selected model does not support reasoning", () => {
        const reasoningOptions = [
            { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
        ];
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                modelOptions={reasoningOptions}
                selectedModel="claude-haiku-5-5"
                selectedReasoningEffort="high"
                onModelChange={vi.fn<(model: string) => void>()}
                onReasoningEffortChange={vi.fn<(effort: string) => void>()}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-haiku-5-5" });
    });

    it("omits both summarization_model and reasoning_effort when selectedModel is unoffered", () => {
        const reasoningOptions = [
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
        ];
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                modelOptions={reasoningOptions}
                selectedModel="retired-unoffered-model"
                selectedReasoningEffort="high"
                onModelChange={vi.fn<(model: string) => void>()}
                onReasoningEffortChange={vi.fn<(effort: string) => void>()}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(routerPost.mock.calls[0][1]).toEqual({});
    });

    it("carries reasoning_effort when the selected model supports reasoning", () => {
        const reasoningOptions = [
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
        ];
        render(
            <LlmSummaryEmptyState
                {...baseProps}
                modelOptions={reasoningOptions}
                selectedModel="Gemini Argon Latest"
                selectedReasoningEffort="high"
                onModelChange={vi.fn<(model: string) => void>()}
                onReasoningEffortChange={vi.fn<(effort: string) => void>()}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "Gemini Argon Latest",
            reasoning_effort: "high",
        });
    });
});
