import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

// @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
vi.mock("@inertiajs/react", () => ({
    router: { post: vi.fn<(...args: unknown[]) => void>(), patch: vi.fn<(...args: unknown[]) => void>() },
    usePage: () => ({ props: {} }),
    useForm: () => ({
        data: {},
        setData: vi.fn<(key: string, value: unknown) => void>(),
        post: vi.fn<() => void>(),
        processing: false,
        errors: {},
        reset: vi.fn<() => void>(),
        transform: vi.fn<() => void>(),
    }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(message: unknown) => void>() }));

import LlmSummaryCompletedView from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedView";
import LlmSummaryDraftNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryDraftNotice";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
const provisioning = (overrides: Partial<IBillLlmProvisioning> = {}): IBillLlmProvisioning => ({
    generation_status: "completed",
    generation_error: null,
    llm_summary: "The unpublished draft.",
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
    testimony_attachments: null,
    citations_valid: null,
    invalid_citations: null,
    ...overrides,
});

describe("LlmSummaryDraftNotice — who wrote the text it is showing", () => {
    it("names the operator when the draft was pasted", () => {
        render(
            <LlmSummaryDraftNotice
                llmDraft="Operator-pasted brief one-line summary."
                llmProvider="operator_paste"
                publishedSummary="The published summary."
                onUseDraft={vi.fn<() => void>()}
            />,
        );

        expect(screen.getByTestId("llm-draft-notice")).toHaveTextContent(/you pasted/i);
        expect(screen.getByTestId("llm-draft-notice")).not.toHaveTextContent(/the model wrote/i);
        expect(screen.getByTestId("llm-draft-notice")).not.toHaveTextContent(/last run/i);
    });

    it("names the model when the draft was generated", () => {
        render(
            <LlmSummaryDraftNotice
                llmDraft="Bought from the model."
                llmProvider="claude"
                publishedSummary="The published summary."
                onUseDraft={vi.fn<() => void>()}
            />,
        );

        expect(screen.getByTestId("llm-draft-notice")).toHaveTextContent(/the model wrote/i);
        expect(screen.getByTestId("llm-draft-notice")).not.toHaveTextContent(/you pasted/i);
    });

    // @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
    it.each(["operator_paste", "claude"])("says the draft is not on the bill (%s)", (llmProvider) => {
        render(
            <LlmSummaryDraftNotice
                llmDraft="Some draft."
                llmProvider={llmProvider}
                publishedSummary="The published summary."
                onUseDraft={vi.fn<() => void>()}
            />,
        );

        expect(screen.getByTestId("llm-draft-notice")).toHaveTextContent(/not on the bill/i);
        expect(screen.getByTestId("btn-use-llm-draft")).toBeInTheDocument();
    });

    // @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
    it("stays on screen after the draft has been copied into the editor but not yet saved", () => {
        // @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
        render(
            <LlmSummaryDraftNotice
                llmDraft="Some draft, now also sitting in the editor."
                llmProvider="claude"
                publishedSummary="The published summary — unchanged, because nothing was saved yet."
                onUseDraft={vi.fn<() => void>()}
            />,
        );

        expect(screen.getByTestId("llm-draft-notice")).toHaveTextContent(/not on the bill/i);
    });

    it("disappears once the published summary actually matches the draft", () => {
        const { container } = render(
            <LlmSummaryDraftNotice
                llmDraft="Same text."
                llmProvider="claude"
                publishedSummary="Same text."
                onUseDraft={vi.fn<() => void>()}
            />,
        );

        expect(container).toBeEmptyDOMElement();
    });
});

// @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
describe("LlmSummaryCompletedView hands the notice the provenance column", () => {
    const renderView = (overrides: Partial<IBillLlmProvisioning>) =>
        render(
            <LlmSummaryCompletedView
                billId={1}
                provisioning={provisioning(overrides)}
                publishedSummary="The published summary an admin wrote."
                isBillPipelineRunning={false}
                runLoading={false}
                isRegenerating={false}
                abandoned={false}
                onConfirmRegenerate={vi.fn<() => void>()}
                modelOptions={[]}
                selectedModel=""
                onModelChange={() => {}}
            />,
        );

    it("labels a pasted draft as the operator's own text", () => {
        renderView({ llm_summary: "Operator-pasted brief one-line summary.", llm_provider: "operator_paste" });

        expect(screen.getByTestId("llm-draft-notice")).toHaveTextContent(/you pasted/i);
    });

    it("labels a generated draft as the model's", () => {
        renderView({ llm_summary: "Bought from the model.", llm_provider: "claude" });

        expect(screen.getByTestId("llm-draft-notice")).toHaveTextContent(/the model wrote/i);
    });
});
