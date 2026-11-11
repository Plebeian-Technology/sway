// LlmSummaryGenerateBranch, LlmSummaryEditableSummary, and LlmSummaryBreakdownToggle were split out
// of BillCreatorLlmSummaryStatus and LlmSummaryCompletedView.

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const routerPatch = vi.fn<(...args: unknown[]) => unknown>();
const notify = vi.fn<(...args: unknown[]) => unknown>();

vi.mock("@inertiajs/react", () => ({
    router: { patch: (...args: unknown[]) => routerPatch(...args) },
    usePage: () => ({ props: { errors: {} } }),
}));

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
    Badge: ({ children, tone, ...props }: React.HTMLAttributes<HTMLSpanElement> & { tone?: string }) => (
        <span data-tone={tone} {...props}>
            {children}
        </span>
    ),
}));

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
}));
// Covered by PasteSummaryDialog.test.tsx — this file only checks that the failed branch mounts it
// and passes this bill's id.
vi.mock("app/frontend/components/admin/creator/PasteSummaryDialog", () => ({
    default: ({ open, billId }: { open: boolean; billId: number }) =>
        open ? <div data-testid="paste-summary-dialog" data-bill-id={billId} /> : null,
}));

import LlmSummaryBreakdownToggle from "app/frontend/components/admin/creator/llm-summary/LlmSummaryBreakdownToggle";
import LlmSummaryEditableSummary from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEditableSummary";
import LlmSummaryGenerateBranch from "app/frontend/components/admin/creator/llm-summary/LlmSummaryGenerateBranch";

beforeEach(() => {
    routerPatch.mockClear();
    notify.mockClear();
});

afterEach(() => cleanup());

describe("LlmSummaryGenerateBranch", () => {
    const baseProps = {
        billId: 42,
        generationError: null,
        onGenerate: vi.fn<() => void>(),
        // What used to be one `disabled` flag is now two separate reasons, so
        // aria-describedby can point at the right explanation.
        isBillPipelineRunning: false,
        isRegenerating: false,
        // The server's "nothing is writing to this row" judgement. False here — abandoned-row
        // cases are pinned in BillCreatorLlmSummaryStatus.test.tsx. (C24-01)
        abandoned: false,
        hasTestimony: false,
    };

    it("not-generated (null) status renders an enabled Generate button", () => {
        const onGenerate = vi.fn<() => void>();
        render(<LlmSummaryGenerateBranch {...baseProps} status={null} onGenerate={onGenerate} />);

        expect(screen.getByTestId("llm-status-badge").textContent).toBe("Not generated");
        expect(screen.queryByTestId("llm-error-message")).toBeNull();

        const btn = screen.getByTestId("btn-generate-summary") as HTMLButtonElement;
        expect(btn.textContent).toBe("Generate summary");
        expect(btn.disabled).toBe(false);

        fireEvent.click(btn);
        expect(onGenerate).toHaveBeenCalledTimes(1);
    });

    it("skipped status (no prior summary) renders the 'Skipped' badge and an enabled Generate button", () => {
        const onGenerate = vi.fn<() => void>();
        render(<LlmSummaryGenerateBranch {...baseProps} status="skipped" onGenerate={onGenerate} />);

        expect(screen.getByTestId("llm-status-badge").textContent).toBe("Skipped");
        // A skip means something else took over, not that anything broke, so
        // no pipeline-error block shows.
        expect(screen.queryByTestId("llm-error-message")).toBeNull();

        const btn = screen.getByTestId("btn-generate-summary") as HTMLButtonElement;
        expect(btn.textContent).toBe("Generate summary");
        expect(btn.disabled).toBe(false);

        fireEvent.click(btn);
        expect(onGenerate).toHaveBeenCalledTimes(1);
    });

    it("pending status renders a disabled, action-less button", () => {
        const onGenerate = vi.fn<() => void>();
        render(<LlmSummaryGenerateBranch {...baseProps} status="pending" onGenerate={onGenerate} />);

        expect(screen.getByTestId("llm-status-badge").textContent).toBe("Queued…");

        const btn = screen.getByTestId("btn-generate-summary") as HTMLButtonElement;
        expect(btn.disabled).toBe(true);
        fireEvent.click(btn);
        expect(onGenerate).not.toHaveBeenCalled();
    });

    it("failed status renders the stored reason and a Retry button that fires onGenerate", () => {
        const onGenerate = vi.fn<() => void>();
        render(
            <LlmSummaryGenerateBranch
                {...baseProps}
                status="failed"
                generationError="boom: extraction failed"
                onGenerate={onGenerate}
            />,
        );

        expect(screen.getByTestId("llm-status-badge").textContent).toBe("Failed");
        expect(screen.getByTestId("llm-error-message").textContent).toContain("boom: extraction failed");

        const btn = screen.getByTestId("btn-retry-summary") as HTMLButtonElement;
        expect(btn.textContent).toBe("Retry");
        fireEvent.click(btn);
        expect(onGenerate).toHaveBeenCalledTimes(1);
    });

    it("failed status with no error message falls back to copy naming the two ways out", () => {
        render(<LlmSummaryGenerateBranch {...baseProps} status="failed" generationError={null} />);

        expect(screen.getByTestId("llm-error-message").textContent).toContain("Retry, or paste a summary instead");
    });

    // generation_error is always a summary-run fact, never a pipeline error — copy here must not
    // blame the pipeline or point at Solid Queue logs (SSH-only access). (FE26-04)
    it("does not blame the pipeline or send the operator to a log they cannot open", () => {
        const { rerender } = render(
            <LlmSummaryGenerateBranch
                {...baseProps}
                status="failed"
                generationError="no summary was generated: this bill has no extracted text"
            />,
        );

        const withReason = screen.getByTestId("llm-error-message");
        expect(withReason).toHaveTextContent(/this bill has no extracted text/i);
        expect(withReason.textContent ?? "").not.toMatch(/pipeline|solid queue/i);

        rerender(<LlmSummaryGenerateBranch {...baseProps} status="failed" generationError={null} />);
        expect(screen.getByTestId("llm-error-message").textContent ?? "").not.toMatch(/pipeline|solid queue/i);
    });

    // No writer sets generation_error on a skipped row (mark_stale_skipped!/reclaim_abandoned_run!
    // leave it null) — tests pass the only real state. (C20-02)
    describe("a skipped row", () => {
        it("says why the Generate button is back, on a row carrying no stored reason", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="skipped" generationError={null} />);

            const notice = screen.getByTestId("llm-skip-notice");
            expect(notice.textContent).toMatch(/waited in the queue/i);
            // Not "Generate again": this same notice also draws on
            // LlmSummaryCompletedView, whose button reads "Regenerate
            // summary", not "Generate".
            expect(notice.textContent).toMatch(/try again/i);
        });

        it("does not call the skip a failure", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="skipped" generationError={null} />);

            expect(screen.getByTestId("llm-skip-notice").textContent).not.toMatch(/failed generation|error/i);
            expect(screen.queryByTestId("llm-error-message")).toBeNull();
        });

        // @lat: [[skipped-run-notice-copy#The STALE_AFTER skip is not a dead worker]]
        it("does not send the operator looking for a dead worker", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="skipped" generationError={null} />);

            const notice = screen.getByTestId("llm-skip-notice");
            expect(notice.textContent).not.toMatch(/nothing picked it up/i);
            expect(notice.textContent).toMatch(/passed it over/i);
        });

        it("still calls a failure a failure, and draws no skip notice", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="failed" generationError="boom" />);

            expect(screen.getByTestId("llm-error-message").textContent).toMatch(/failed/i);
            expect(screen.queryByTestId("llm-skip-notice")).toBeNull();
        });

        // @lat: [[skipped-run-notice-copy#The reclaim-sweep copy test notes (LlmSummaryStatusBranches.test.tsx)]]
        it("shows the server's reason when a skipped row carries one", () => {
            const released =
                "This summary run never started. Nothing wrote to it for over 1 hour, so Sway released it. " +
                "It made no calls, so nothing was charged, and anything you typed was saved. Any summary " +
                "on this bill was already there before this run. Start a new run when you are ready.";
            render(<LlmSummaryGenerateBranch {...baseProps} status="skipped" generationError={released} />);

            const notice = screen.getByTestId("llm-skip-notice");
            expect(notice.textContent).toContain(released);
            // And not the other cause on top of it: the row did not wait in the
            // queue, it was released.
            expect(notice.textContent).not.toMatch(/waited in the queue/i);
        });
    });

    // Check each of the two reasons on its own. Splitting the old single
    // `disabled` prop is only worth doing if each reason still disables.
    it.each(["isBillPipelineRunning", "isRegenerating"] as const)("%s disables the Generate button", (reason) => {
        render(<LlmSummaryGenerateBranch {...baseProps} status={null} {...{ [reason]: true }} />);

        expect((screen.getByTestId("btn-generate-summary") as HTMLButtonElement).disabled).toBe(true);
    });

    // Only the running-pipeline case has a notice on screen to point at.
    it("describes a pipeline-disabled Generate, and not a regeneration-disabled one", () => {
        const { rerender } = render(
            <LlmSummaryGenerateBranch {...baseProps} status={null} isBillPipelineRunning={true} />,
        );
        expect(screen.getByTestId("btn-generate-summary")).toHaveAttribute(
            "aria-describedby",
            "bill-pipeline-busy-notice",
        );

        rerender(<LlmSummaryGenerateBranch {...baseProps} status={null} isRegenerating={true} />);
        expect(screen.getByTestId("btn-generate-summary")).not.toHaveAttribute("aria-describedby");
    });

    // The paste fallback used to be reachable only from LlmSummaryCompletedView — unreachable from
    // the failed state, where Retry alone re-pays for both LLM calls.
    describe("manual paste fallback on the failed branch", () => {
        it("offers Paste summary JSON alongside Retry and opens the dialog for this bill", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="failed" generationError="boom" />);

            expect(screen.getByTestId("btn-retry-summary")).toBeInTheDocument();
            expect(screen.queryByTestId("paste-summary-dialog")).toBeNull();

            fireEvent.click(screen.getByTestId("btn-paste-summary-fallback"));

            const dialog = screen.getByTestId("paste-summary-dialog");
            expect(dialog.getAttribute("data-bill-id")).toBe("42");
        });

        // @lat: [[bill-summary-supersede-gate#The Bill Creator's paste fallback on a skipped row]]
        it("offers it on a skipped row, which has no writer and no job coming", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="skipped" />);

            fireEvent.click(screen.getByTestId("btn-paste-summary-fallback"));

            expect(screen.getByTestId("paste-summary-dialog").getAttribute("data-bill-id")).toBe("42");
        });

        it("offers it on a pending row, which is the case the supersede gate was written for", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status="pending" />);

            expect(screen.getByTestId("btn-paste-summary-fallback")).toBeInTheDocument();
        });

        it("does not offer it on a never-generated row — nothing has failed or been paid for", () => {
            render(<LlmSummaryGenerateBranch {...baseProps} status={null} />);

            expect(screen.queryByTestId("btn-paste-summary-fallback")).toBeNull();
        });
    });
});

describe("LlmSummaryEditableSummary", () => {
    it("seeds the textarea from initialSummary and PATCHes the edited value on save", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        const textarea = screen.getByTestId("textarea-llm-summary") as HTMLTextAreaElement;
        expect(textarea.value).toBe("Original body");

        fireEvent.change(textarea, { target: { value: "Edited body" } });
        fireEvent.click(screen.getByTestId("btn-save-summary"));

        expect(routerPatch).toHaveBeenCalledTimes(1);
        const [url, body, opts] = routerPatch.mock.calls[0] as unknown[];
        expect(url).toBe("/bills/7");
        expect(body).toEqual({
            summary: "Edited body",
            return_tab: "summary",
            news_usage: "none",
            source_uses: [],
        });
        const optsObj = opts as {
            preserveScroll?: boolean;
            onSuccess?: (result: unknown) => void;
            onError?: () => void;
        };
        expect(optsObj).toMatchObject({ preserveScroll: true });
        expect(typeof optsObj.onSuccess).toBe("function");
    });

    // Without onError a refused save was silent — flash-to-toast only reads flash.notice/alert,
    // never props.errors, and this textarea never re-reads the server value.
    it("tells the operator when the server refuses the save", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));

        const [, , opts] = routerPatch.mock.calls[0] as unknown[];
        const optsObj = opts as { onError?: () => void };
        expect(typeof optsObj.onError).toBe("function");

        optsObj.onError?.();
        expect(notify).toHaveBeenCalledWith(
            expect.objectContaining({ level: "error", title: expect.stringMatching(/Summary could not be saved/i) }),
        );
    });

    // onError never fires on redirects — a valid-page landing is Inertia success. A lapsed admin
    // redirect to / used to toast "Summary saved." over an unsaved change. (C20-05)
    it("does not claim success when the visit lands somewhere other than this bill", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));
        const [, , opts] = routerPatch.mock.calls[0] as unknown[];
        const optsObj = opts as { onSuccess?: (result: unknown) => void };

        // props is present on every real Inertia page, so a fixture that omits
        // it describes a page that cannot exist. It has to be here for the
        // page-expired check to read (C21-01).
        optsObj.onSuccess?.({ url: "/", props: { flash: {} } });
        expect(notify).toHaveBeenCalledWith(
            expect.objectContaining({ level: "error", title: expect.stringMatching(/sign in as an admin/i) }),
        );
        expect(notify).not.toHaveBeenCalledWith(expect.objectContaining({ level: "success" }));
    });

    // @lat: [[bill-creator-landed-write-detection#One reachable case, not two#LlmSummaryEditableSummary's defensive non-bill-landing test]]
    it("claims no success for any landing page that is not this bill's", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));
        const [, , opts] = routerPatch.mock.calls[0] as unknown[];
        const optsObj = opts as { onSuccess?: (result: unknown) => void };

        optsObj.onSuccess?.({ url: "/admin/bill_creator/new", props: { flash: {} } });
        expect(notify).not.toHaveBeenCalledWith(expect.objectContaining({ level: "success" }));
    });

    // @lat: [[page-expired-flash-flag-and-c21-01#LlmSummaryEditableSummary's page-expired test note]]
    it("does not claim success when the page expired and the save was refused", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));
        const [, , opts] = routerPatch.mock.calls[0] as unknown[];
        const optsObj = opts as { onSuccess?: (result: unknown) => void };

        optsObj.onSuccess?.({
            url: "/admin/bill_creator/7/summary",
            props: { flash: { page_expired: true, alert: "The page expired, please try again." } },
        });

        expect(notify).not.toHaveBeenCalledWith(expect.objectContaining({ level: "success" }));
        expect(notify).toHaveBeenCalledWith(
            expect.objectContaining({ level: "error", title: expect.stringMatching(/page expired|not saved/i) }),
        );
    });

    // Inertia already follows the CSRF-rescue redirect with a GET (fresh XSRF cookie included) —
    // telling the operator to reload asks them to redo it by hand. (C22-08)
    it("does not tell the operator to reload when the page expired", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));
        const [, , opts] = routerPatch.mock.calls[0] as unknown[];
        const optsObj = opts as { onSuccess?: (result: unknown) => void };

        optsObj.onSuccess?.({
            url: "/admin/bill_creator/7/summary",
            props: { flash: { page_expired: true, alert: "The page expired, please try again." } },
        });

        const [notifyCall] = notify.mock.calls[0] as unknown[];
        const { title } = notifyCall as { title?: string };
        expect(title).not.toMatch(/reload|refresh/i);
        expect(title).toMatch(/save again/i);
    });

    // The other direction. A save that really did land must still say so, or a
    // handler that had simply stopped toasting would pass both examples above.
    it("still says the summary was saved when the visit comes back on this bill", () => {
        render(
            <LlmSummaryEditableSummary
                billId={7}
                publishedSummary="Original body"
                llmDraft={null}
                llmProvider={null}
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));
        const [, , opts] = routerPatch.mock.calls[0] as unknown[];
        const optsObj = opts as { onSuccess?: (result: unknown) => void };

        optsObj.onSuccess?.({ url: "/admin/bill_creator/7/creator?event_key=legislator_votes", props: { flash: {} } });
        expect(notify).toHaveBeenCalledWith(expect.objectContaining({ level: "success", title: "Summary saved." }));
    });
});

describe("LlmSummaryBreakdownToggle", () => {
    it("hides the breakdown until toggled, then hides it again", () => {
        render(<LlmSummaryBreakdownToggle breakdown="Section 1 — detail" />);

        const toggle = screen.getByTestId("btn-toggle-breakdown");
        expect(toggle.textContent).toBe("Show full section breakdown");
        expect(screen.queryByTestId("llm-full-breakdown")).toBeNull();

        fireEvent.click(toggle);
        expect(screen.getByTestId("llm-full-breakdown").textContent).toContain("Section 1 — detail");
        expect(toggle.textContent).toBe("Hide full section breakdown");

        fireEvent.click(toggle);
        expect(screen.queryByTestId("llm-full-breakdown")).toBeNull();
    });

    // @lat: [[bill-creator-summary-tab#Why a run with no breakdown says so]]
    it("says the run wrote no breakdown instead of offering an empty disclosure", () => {
        render(<LlmSummaryBreakdownToggle breakdown={null} />);

        expect(screen.queryByTestId("btn-toggle-breakdown")).toBeNull();
        expect(screen.getByTestId("llm-breakdown-absent").textContent).toContain("wrote no section breakdown");
    });

    it("treats a whitespace-only breakdown as no breakdown", () => {
        render(<LlmSummaryBreakdownToggle breakdown={"   \n  "} />);

        expect(screen.queryByTestId("btn-toggle-breakdown")).toBeNull();
        expect(screen.getByTestId("llm-breakdown-absent")).toBeTruthy();
    });
});
