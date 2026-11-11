import { fireEvent, render as rtlRender, screen } from "@testing-library/react";
import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";
import { usePage } from "@inertiajs/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    router: {
        post: vi.fn<(url: string, data?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown) => void>(),
    },
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
    useForm: () => ({
        data: {},
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        post: vi.fn<() => void>(),
        processing: false,
        errors: {},
        reset: vi.fn<() => void>(),
        transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
    }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(message: string, type?: string) => void>() }));

import BillCreatorLlmSummaryStatus from "app/frontend/components/admin/creator/llm-summary/BillCreatorLlmSummaryStatus";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[private-individual-guard-override#Approve-anyway lives behind the app-wide confirm dialog]]
const render = (ui: React.ReactElement) => rtlRender(ui, { wrapper: ConfirmProvider });

// @lat: [[bill-creator-llm-summary-status-test-notes#Why this file exists as a second mount point]]
const provisioning = (overrides: Partial<IBillLlmProvisioning> = {}): IBillLlmProvisioning => ({
    generation_status: "failed",
    generation_error: "The model timed out.",
    llm_summary: null,
    llm_full_breakdown: null,
    supplemental_testimony: null,
    draft_org_positions: null,
    stale: false,
    reclaimable: false,
    paste_owns_summary_run: false,
    stale_change_kind: null,
    stale_change_at: null,
    llm_generated_at: null,
    llm_provider: "claude",
    has_testimony: false,
    testimony_attachments: [
        {
            filename: "testimony-1.pdf",
            download_status: "failed",
            extraction_status: "not_attempted",
            error: "timeout",
        },
    ],
    citations_valid: true,
    invalid_citations: [],
    ...overrides,
});

const mockActiveRun = (run: { status?: string | null; bill_id?: number | null } | null) =>
    (usePage as ReturnType<typeof vi.fn>).mockReturnValue({ props: { active_legislation_pipeline_run: run } });

// Every other example in this file relies on the default no-active-run mock —
// without this reset, a B7 example below setting one would leak into whatever
// test happens to run after it.
beforeEach(() => mockActiveRun(null));

const renderStatus = (
    overrides: Partial<IBillLlmProvisioning> = {},
    onGenerate: () => void = vi.fn<() => void>(),
    isBillPipelineRunning = false,
) =>
    render(
        <BillCreatorLlmSummaryStatus
            billId={1}
            provisioning={provisioning(overrides)}
            publishedSummary="The published summary."
            billPipelineStatus={null}
            isBillPipelineRunning={isBillPipelineRunning}
            isRegenerating={false}
            regenLoading={false}
            onRegenerate={vi.fn<() => void>()}
            onGenerate={onGenerate}
            modelOptions={[]}
            selectedModel=""
            onModelChange={() => {}}
        />,
    );

describe("BillCreatorLlmSummaryStatus wiring", () => {
    it("hands the failed branch the server's generation error", () => {
        renderStatus({ generation_error: "Anthropic returned a 529." });

        expect(screen.getByText(/Anthropic returned a 529\./)).toBeInTheDocument();
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Why the abandoned-row notice examples cover four arms]]
    describe("a terminal row that still holds work", () => {
        // @lat: [[bill-creator-summary-tab#Which screen a failed run leaves behind]]
        it("offers a retry on a failed row holding no summary, whatever positions the bill carries", () => {
            renderStatus({ generation_status: "failed", llm_summary: null });

            expect(screen.getByTestId("btn-retry-summary")).toBeInTheDocument();
            expect(screen.queryByTestId("panel-public-summary")).toBeNull();
        });

        // The completed view is reached, so the badge has to be read off the
        // row rather than assumed. A green "Ready" here would be the exact
        // claim the backend settle exists to avoid.
        it("still stamps that row Failed, not Ready", () => {
            renderStatus({ generation_status: "failed", llm_summary: null });

            expect(screen.getByTestId("llm-status-badge")).toHaveTextContent(/failed/i);
        });

        it("shows a failed row's summary when the positions half is what broke", () => {
            renderStatus({ generation_status: "failed", llm_summary: "A real summary." });

            expect(screen.getByTestId("llm-status-badge")).toHaveTextContent(/failed/i);
            // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
            expect(screen.getByTestId("llm-draft-body")).toHaveTextContent("A real summary.");
        });

        it("shows a failed row's reason beside the retry it offers", () => {
            const noSourceText =
                "no summary was generated: this bill has no extracted text and no diff markdown, " +
                "so there was nothing to summarize.";
            renderStatus({ generation_status: "failed", llm_summary: null, generation_error: noSourceText });

            expect(screen.getByTestId("llm-error-message")).toHaveTextContent(noSourceText);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("says a draft survived the failure without saying which run wrote it", () => {
            renderStatus({ generation_status: "failed", llm_summary: "A real summary." });

            const notice = screen.getByTestId("llm-generation-error");
            expect(notice).toHaveTextContent(/a draft summary is still on this bill/i);
            expect(notice).not.toHaveTextContent(/earlier run/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("makes no claim about who wrote the draft on a row the sweep released", () => {
            // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
            const releasedInFlight =
                "This summary run stopped part-way. Nothing wrote to it for over 1 hour, so Sway released it. " +
                "It may already have paid for a call, and it may have saved part of its work. Anything you " +
                "typed was saved. Check what is on this bill before you start a new run.";
            renderStatus({
                generation_status: "failed",
                llm_summary: "A summary this run already paid for.",
                generation_error: releasedInFlight,
            });

            const notice = screen.getByTestId("llm-generation-error");
            expect(notice.textContent).toContain(releasedInFlight);
            expect(notice).not.toHaveTextContent(/earlier run/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("does not call the editor's text the earlier run's output", () => {
            render(
                <BillCreatorLlmSummaryStatus
                    billId={1}
                    provisioning={provisioning({ generation_status: "failed", llm_summary: "The model's draft." })}
                    publishedSummary="Summary pending"
                    billPipelineStatus={null}
                    isBillPipelineRunning={false}
                    isRegenerating={false}
                    regenLoading={false}
                    onRegenerate={vi.fn<() => void>()}
                    onGenerate={vi.fn<() => void>()}
                    modelOptions={[]}
                    selectedModel=""
                    onModelChange={() => {}}
                />,
            );

            const notice = screen.getByTestId("llm-generation-error");
            expect(notice).not.toHaveTextContent(/above/i);
            expect(notice).toHaveTextContent(/a draft summary is still on this bill/i);
        });

        it("claims no surviving draft when the row holds none", () => {
            renderStatus({ generation_status: "failed", llm_summary: null });

            expect(screen.getByTestId("llm-error-message")).not.toHaveTextContent(/draft/i);
            expect(screen.queryByTestId("llm-generation-error")).toBeNull();
        });

        // The other side of that wire: a `completed` row must not draw the
        // failure notice, so the assertion above cannot pass on a component
        // that ignores the status.
        // A first run producing nothing must still reach the generate branch and its Retry button
        // (btn-retry-summary; btn-generate-summary is the not-yet-generated spelling).
        it("routes an empty failed row to the generate branch", () => {
            renderStatus({ generation_status: "failed", llm_summary: null });

            // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
            expect(screen.getByTestId("btn-retry-summary")).toBeInTheDocument();
        });
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("a queued or running row that still holds the last run's work", () => {
        it("keeps a pending row on the completed view", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            expect(screen.getByTestId("panel-public-summary")).toBeInTheDocument();
        });

        it("keeps a pending row's summary on screen", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
            expect(screen.getByTestId("llm-draft-body")).toHaveTextContent("A real summary.");
        });

        // The completed view is reached, so the badge has to be read off the
        // row. A green "Ready" over a run that has not started would be the
        // same lie the terminal branch above guards against.
        it("still stamps that row Queued, not Ready", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            expect(screen.getByTestId("llm-status-badge")).toHaveTextContent(/queued/i);
        });

        it("says on screen that the work shown is from the last run", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            expect(screen.getByTestId("llm-run-in-flight")).toHaveTextContent(/from the last run/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Why the ordinary-generating example is not redundant with the pending one]]
        it("does not date the draft to an earlier run while a run is writing", () => {
            renderStatus({ generation_status: "generating", llm_summary: "A real summary.", reclaimable: false });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            expect(notice).not.toMatch(/from the last run/i);
            expect(notice).toMatch(/the draft summary on this bill/i);
            // Still the live arm: there IS a run, and it does replace the work.
            expect(notice).toMatch(/the new run replaces it when it finishes/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("does not credit an operator's own paste to a run", () => {
            renderStatus({
                generation_status: "pending",
                llm_summary: "I typed this.",
                llm_provider: "operator_paste",
            });

            const notice = screen.getByTestId("llm-run-in-flight");
            expect(notice).toHaveTextContent(/the summary you pasted/i);
            expect(notice.textContent ?? "").not.toMatch(/summary from the last run/i);
            expect(notice.textContent ?? "").not.toMatch(/model's draft summary/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("does not promise a run will replace the published summary", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            expect(screen.getByTestId("llm-run-in-flight")).toHaveTextContent(
                /published summary in the box below is not changed by a run/i,
            );
        });

        // @lat: [[bill-creator-summary-tab#Why the summary tab's in-flight notice says nothing about positions]]
        it("says the draft summary is replaced, and names nothing else the run touches", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            const notice = screen.getByTestId("llm-run-in-flight");
            expect(notice).toHaveTextContent(/replaces it when it finishes/i);
            expect(notice.textContent ?? "").not.toMatch(/draft position/i);
            expect(notice.textContent ?? "").not.toMatch(/approve/i);
        });

        // The completed view's Regenerate button buys paid model calls. Reaching
        // that view from a row that already has a run queued must not hand the
        // operator a second one.
        it("switches off Regenerate while a run is already queued", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary." });

            expect(screen.getByTestId("btn-regenerate-summary")).toBeDisabled();
        });

        it("keeps a generating row on the completed view", () => {
            renderStatus({ generation_status: "generating", llm_summary: "A real summary." });

            expect(screen.getByTestId("panel-public-summary")).toBeInTheDocument();
        });

        // The other side of the wire, three ways: a row with nothing on it
        // keeps its own plain panel, so none of the examples above can pass on
        // a component that sends every row to the completed view.
        it("leaves an empty generating row on the generating panel", () => {
            renderStatus({ generation_status: "generating", llm_summary: null });

            expect(screen.getByText("Generating summary…")).toBeInTheDocument();
            expect(screen.queryByTestId("llm-run-in-flight")).toBeNull();
        });

        it("leaves an empty pending row on the generate branch", () => {
            renderStatus({ generation_status: "pending", llm_summary: null });

            expect(screen.getByTestId("btn-generate-summary")).toBeInTheDocument();
        });

        it("draws no in-flight notice on a finished row", () => {
            renderStatus({ generation_status: "completed", llm_summary: "A real summary." });

            expect(screen.queryByTestId("llm-run-in-flight")).toBeNull();
            expect(screen.getByTestId("btn-regenerate-summary")).not.toBeDisabled();
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("switches off Regenerate while a run is already generating, not only while it is queued", () => {
            renderStatus({ generation_status: "generating", llm_summary: "A real summary." });

            expect(screen.getByTestId("btn-regenerate-summary")).toBeDisabled();
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("does not re-open the regenerate dialog by itself when the run settles", () => {
            const { rerender } = render(
                <BillCreatorLlmSummaryStatus
                    billId={1}
                    provisioning={provisioning({ generation_status: "completed", llm_summary: "A real summary." })}
                    publishedSummary="The published summary."
                    billPipelineStatus={null}
                    isBillPipelineRunning={false}
                    isRegenerating={false}
                    regenLoading={false}
                    onRegenerate={vi.fn<() => void>()}
                    onGenerate={vi.fn<() => void>()}
                    modelOptions={[]}
                    selectedModel=""
                    onModelChange={() => {}}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            expect(screen.getByTestId("confirmation-dialog")).toBeInTheDocument();

            const at = (status: IBillLlmProvisioning["generation_status"]) => (
                <BillCreatorLlmSummaryStatus
                    billId={1}
                    provisioning={provisioning({ generation_status: status, llm_summary: "A real summary." })}
                    publishedSummary="The published summary."
                    billPipelineStatus={null}
                    isBillPipelineRunning={false}
                    isRegenerating={false}
                    regenLoading={false}
                    onRegenerate={vi.fn<() => void>()}
                    onGenerate={vi.fn<() => void>()}
                    modelOptions={[]}
                    selectedModel=""
                    onModelChange={() => {}}
                />
            );

            // Somebody else starts a run: the poll delivers `pending`, and the
            // dialog goes away.
            rerender(at("pending"));
            expect(screen.queryByTestId("confirmation-dialog")).toBeNull();

            // That run settles. The dialog must stay shut.
            rerender(at("failed"));
            expect(screen.queryByTestId("confirmation-dialog")).toBeNull();
        });
    });
});

// @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
describe("BillCreatorLlmSummaryStatus — an empty generating row", () => {
    const abandoned = {
        generation_status: "generating" as const,
        llm_summary: null,
        draft_org_positions: null,
        llm_generated_at: null,
        testimony_attachments: [],
    };

    it("offers a way out once the server says the row has no live writer", () => {
        const onGenerate = vi.fn<() => void>();
        renderStatus({ ...abandoned, reclaimable: true }, onGenerate);

        const button = screen.getByTestId("btn-start-new-run");
        expect(button).toHaveTextContent(/generate summary/i);
        expect(button).not.toBeDisabled();

        fireEvent.click(button);
        expect(onGenerate).toHaveBeenCalledTimes(1);
    });

    it("says why the button is there, and what it costs", () => {
        renderStatus({ ...abandoned, reclaimable: true, has_testimony: true });

        const notice = screen.getByTestId("llm-abandoned-run-notice").textContent ?? "";
        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        expect(notice).toMatch(/stopped part-way/i);
        expect(notice).toMatch(/no more than two model calls/i);
        // No surface here may ask for a manual refresh, and this one least of
        // all: the sweep and the poll between them settle it with nothing done.
        expect(notice).not.toMatch(/reload|refresh/i);
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    it("keeps the button shut while the run is genuinely still going", () => {
        renderStatus({ ...abandoned, reclaimable: false });

        expect(screen.queryByTestId("llm-abandoned-run-notice")).toBeNull();
        expect(screen.getByRole("button", { name: /generating…/i })).toBeDisabled();
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    it("points a screen reader at the pipeline-busy notice, and can be found by a gate", () => {
        renderStatus({ ...abandoned, reclaimable: true }, vi.fn<() => void>(), true);

        const button = screen.getByTestId("btn-start-new-run");
        expect(button).toHaveAttribute("aria-describedby", "bill-pipeline-busy-notice");
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("what starting a new run actually buys", () => {
        it("names both halves when the bill has testimony", () => {
            renderStatus({ ...abandoned, reclaimable: true, has_testimony: true });

            const notice = screen.getByTestId("llm-abandoned-run-notice");
            expect(notice).toHaveTextContent(/no more than two model calls/i);
            expect(notice).toHaveTextContent(/organization positions/i);
        });

        it("promises no organization positions on a bill with no testimony", () => {
            renderStatus({ ...abandoned, reclaimable: true, has_testimony: false });

            const notice = screen.getByTestId("llm-abandoned-run-notice");
            expect(notice).toHaveTextContent(/no testimony/i);
            expect(notice).toHaveTextContent(/no more than one model call/i);
            expect(notice).not.toHaveTextContent(/two model calls/i);
        });
    });
});

// @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
describe("BillCreatorLlmSummaryStatus — every branch a reclaimable row reaches", () => {
    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("an empty pending row", () => {
        it("opens the Generate button once the server says nothing is writing to it", () => {
            renderStatus({ generation_status: "pending", llm_summary: null, reclaimable: true });

            expect(screen.getByTestId("btn-generate-summary")).not.toBeDisabled();
            expect(screen.getByTestId("llm-abandoned-run-notice")).toBeInTheDocument();
        });

        it("keeps it shut while the queued run is genuinely still waiting", () => {
            renderStatus({ generation_status: "pending", llm_summary: null, reclaimable: false });

            expect(screen.getByTestId("btn-generate-summary")).toBeDisabled();
            expect(screen.queryByTestId("llm-abandoned-run-notice")).toBeNull();
        });
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("a stuck row that still holds the last run's work", () => {
        it.each([
            ["generating", "generating" as const],
            ["pending", "pending" as const],
        ])("opens Regenerate on an abandoned %s row", (_label, status) => {
            renderStatus({ generation_status: status, llm_summary: "A real summary.", reclaimable: true });

            expect(screen.getByTestId("btn-regenerate-summary")).not.toBeDisabled();
        });

        it.each([
            ["generating", "generating" as const],
            ["pending", "pending" as const],
        ])("keeps Regenerate shut on a live %s row", (_label, status) => {
            renderStatus({ generation_status: status, llm_summary: "A real summary.", reclaimable: false });

            expect(screen.getByTestId("btn-regenerate-summary")).toBeDisabled();
        });

        // The panel's own words were the other half of the defect: it told the
        // operator a run was on its way over a row nothing was working on.
        it("stops the panel promising a run that is not coming", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight");
            expect(notice).toHaveTextContent(/never started, and nothing is working on it now/i);
            expect(notice).not.toHaveTextContent(/replaces it when it finishes/i);
        });

        it("still promises the replacement while a run really is coming", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: false });

            const notice = screen.getByTestId("llm-run-in-flight");
            expect(notice).toHaveTextContent(/replaces it when it finishes/i);
            expect(notice).not.toHaveTextContent(/nothing is working on it now/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("does not tell the operator to wait for a run that finished", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: true });

            expect(screen.getByTestId("llm-run-in-flight")).not.toHaveTextContent(/a run that finished/i);
        });

        // The other side: the notice still has to say what an abandoned run
        // leaves behind, or one that had simply dropped the sentence would pass
        // the example above. Approve belongs to the positions tab now — see
        // PositionsApproveGating.test.tsx.
        // @lat: [[bill-creator-summary-tab#Why the summary tab's in-flight notice says nothing about positions]]
        it("still says the run stopped and what to do about it", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight");
            expect(notice).toHaveTextContent(/regenerate to start a new one/i);
            expect(notice.textContent ?? "").not.toMatch(/approve/i);
        });
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("a stuck row whose pipeline data has moved on", () => {
        const staleRow = {
            generation_status: "pending" as const,
            llm_summary: "A real summary.",
            stale: true,
            stale_change_kind: "pipeline_data" as const,
            stale_change_at: "2026-08-05T00:00:00Z",
        };

        it("opens the out-of-date header's button on an abandoned row", () => {
            renderStatus({ ...staleRow, reclaimable: true });

            expect(screen.getByTestId("btn-regenerate-from-latest-data")).not.toBeDisabled();
        });

        it("keeps it shut while the queued run is genuinely still waiting", () => {
            renderStatus({ ...staleRow, reclaimable: false });

            expect(screen.getByTestId("btn-regenerate-from-latest-data")).toBeDisabled();
        });
    });

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("a released row that still holds an earlier summary", () => {
        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        const released =
            "This summary run never started. Nothing wrote to it for over 1 hour, so Sway released it. " +
            "It made no calls, so nothing was charged, and anything you typed was saved. Any summary " +
            "on this bill was already there before this run. Start a new run when you are ready.";

        it("shows the sweep's reason on the view a released regeneration lands on", () => {
            renderStatus({
                generation_status: "skipped",
                llm_summary: "A real summary.",
                generation_error: released,
            });

            expect(screen.getByTestId("llm-skip-notice").textContent).toContain(released);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("makes no claim about who wrote the draft it says survived", () => {
            renderStatus({
                generation_status: "skipped",
                llm_summary: "Hand-written by the operator over an afternoon.",
                generation_error: released,
            });

            const notice = screen.getByTestId("llm-skip-notice");
            expect(notice).toHaveTextContent(/a draft summary is still on this bill/i);
            expect(notice).not.toHaveTextContent(/earlier run/i);
            expect(notice).not.toHaveTextContent(/model's draft/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
        it("draws no skip notice on a completed row", () => {
            renderStatus({
                generation_status: "completed",
                llm_summary: "A real summary.",
                generation_error: "positions not saved: the model timed out",
            });

            expect(screen.queryByTestId("llm-skip-notice")).toBeNull();
        });
    });
});

// @lat: [[bill-creator-llm-summary-status-test-notes#Why the abandoned-row notice examples cover four arms]]
describe("BillCreatorLlmSummaryStatus — what the browser says became of a stuck run", () => {
    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    const NEVER_STARTED = /never started/i;
    const STOPPED_PART_WAY = /stopped part-way/i;

    // @lat: [[bill-creator-llm-summary-status-test-notes#Further scattered test notes]]
    describe("a stuck row that still holds work", () => {
        it("says the queued run never started, over a pending row", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            expect(notice).toMatch(NEVER_STARTED);
            expect(notice).not.toMatch(STOPPED_PART_WAY);
        });

        it("says the run stopped part-way, over a generating row", () => {
            renderStatus({ generation_status: "generating", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            expect(notice).toMatch(STOPPED_PART_WAY);
            expect(notice).not.toMatch(NEVER_STARTED);
        });

        // This notice calls the FINISHED run "the last run" here but "the new run" on its live arm — the
        // abandoned arm called the queued run "the last run" too, so neither name was reliable.
        it("keeps one name for each of the two runs it talks about", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            // The draft on screen is the finished run's.
            expect(notice).toMatch(/the draft summary from the last run/i);
            // What never started is the queued one.
            expect(notice).toMatch(/the new run never started/i);
            expect(notice).not.toMatch(/the last run (never started|stopped)/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Why the ordinary-generating example is not redundant with the pending one]]
        it("does not credit a stuck generating run's own draft to some run before it", () => {
            renderStatus({ generation_status: "generating", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            // Nothing here may say the draft belongs to a different run…
            expect(notice).not.toMatch(/from the last run/i);
            // …nor that the run that stopped is a different one from that.
            expect(notice).not.toMatch(/the new run/i);
            // What IS provable: there is a draft, and nothing is working on it.
            expect(notice).toMatch(/the draft summary on this bill/i);
            expect(notice).toMatch(/nothing is working on it now/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Why the paste-carrying-row example exists]]
        it("does not tell a pasted row to buy a run that would delete its text", () => {
            renderStatus({
                generation_status: "pending",
                llm_summary: "I typed this.",
                llm_provider: "operator_paste",
                paste_owns_summary_run: true,
                reclaimable: true,
            });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            expect(notice).not.toMatch(/regenerate to start a new one/i);
            expect(notice).toMatch(/keeps your text/i);
            expect(notice).toMatch(/regenerating would replace it/i);
        });

        // @lat: [[bill-creator-llm-summary-status-test-notes#Why the fixture disagrees the two paste columns on purpose]]
        it("offers Regenerate to a paste that was already regenerated once", () => {
            renderStatus({
                generation_status: "pending",
                llm_summary: "I typed this.",
                // Who wrote the text: still the operator, and the notice
                // above still says so.
                llm_provider: "operator_paste",
                // Who owns the row: nobody the sweep will hand off to.
                paste_owns_summary_run: false,
                reclaimable: true,
            });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            expect(notice).toMatch(/regenerate to start a new one/i);
            expect(notice).not.toMatch(/there is nothing to do/i);
            expect(notice).not.toMatch(/keeps your text/i);
            // The provenance clause is the other column's, and it is unchanged:
            // the text on screen really is the operator's.
            expect(notice).toMatch(/the summary you pasted/i);
        });

        // The other side, so the branch cannot widen into every stuck row. A row
        // with no paste marker IS released with one of the two constants, and
        // Regenerate is the exit it needs.
        it("still offers Regenerate to a stuck row nobody pasted into", () => {
            renderStatus({ generation_status: "pending", llm_summary: "A real summary.", reclaimable: true });

            const notice = screen.getByTestId("llm-run-in-flight").textContent ?? "";
            expect(notice).toMatch(/regenerate to start a new one/i);
        });
    });

    // A row carrying nothing reaches one of two panels, chosen by which status
    // the worker died in, and both draw LlmSummaryAbandonedRunNotice.
    describe("a stuck row with nothing on it", () => {
        it("says the run never started, on the empty pending panel", () => {
            renderStatus({ generation_status: "pending", llm_summary: null, reclaimable: true });

            const notice = screen.getByTestId("llm-abandoned-run-notice").textContent ?? "";
            expect(notice).toMatch(NEVER_STARTED);
            expect(notice).not.toMatch(STOPPED_PART_WAY);
        });

        it("says the run stopped part-way, on the empty generating panel", () => {
            renderStatus({ generation_status: "generating", llm_summary: null, reclaimable: true });

            const notice = screen.getByTestId("llm-abandoned-run-notice").textContent ?? "";
            expect(notice).toMatch(STOPPED_PART_WAY);
            expect(notice).not.toMatch(NEVER_STARTED);
        });
    });
});

// @lat: [[queued-run-notice-copy#Why LlmSummaryQueuedRunNotice exists]]
describe("a queued run on a row that carries nothing yet", () => {
    it("says a run is queued rather than leaving the panel silent", () => {
        renderStatus({ generation_status: "pending", llm_summary: null });

        expect(screen.getByTestId("llm-queued-run-notice")).toBeInTheDocument();
    });

    // The abandoned notice is the opposite claim — nothing is working on this
    // row — so the two must never be on screen together.
    it("says nothing of the kind once the server calls the row abandoned", () => {
        renderStatus({ generation_status: "pending", llm_summary: null, reclaimable: true });

        expect(screen.queryByTestId("llm-queued-run-notice")).toBeNull();
        expect(screen.getByTestId("llm-abandoned-run-notice")).toBeInTheDocument();
    });
});
