import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

// The completed branch puts PasteSummaryDialog and LlmSummaryEditableSummary on
// the page, and both read Inertia's page props and router. Neither is what
// these tests are about.
vi.mock("@inertiajs/react", () => ({
    router: {
        post: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
    },
    usePage: () => ({ props: {} }),
    useForm: () => ({
        data: {},
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        post: vi.fn<(url?: string, options?: Record<string, unknown>) => void>(),
        processing: false,
        errors: {},
        reset: vi.fn<(...keys: string[]) => void>(),
        transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
    }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(...args: unknown[]) => string>() }));

import LlmSummaryCompletedView from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedView";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[bill-creator-llm-summary-status-test-notes#Why this file exists as a second mount point]]
const provisioning = (overrides: Partial<IBillLlmProvisioning> = {}): IBillLlmProvisioning => ({
    generation_status: "completed",
    generation_error: null,
    llm_summary: "A summary.",
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
    citations_valid: false,
    invalid_citations: ["art_99__sec_1"],
    ...overrides,
});

const renderView = (overrides: Partial<IBillLlmProvisioning> = {}, isRegenerating = false) =>
    render(
        <LlmSummaryCompletedView
            billId={1}
            provisioning={provisioning(overrides)}
            publishedSummary="The published summary."
            isBillPipelineRunning={false}
            runLoading={false}
            isRegenerating={isRegenerating}
            abandoned={false}
            onConfirmRegenerate={vi.fn<() => void>()}
            modelOptions={[]}
            selectedModel=""
            onModelChange={() => {}}
        />,
    );

// @lat: [[bill-creator-completed-view-layout#LlmSummaryRegenerateConfirmDialog and the shell's inert wrapper]]
describe("LlmSummaryCompletedView — the confirm dialog during a regeneration", () => {
    it("closes an open dialog once a regeneration starts", () => {
        const { rerender } = renderView();
        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByTestId("confirmation-dialog")).toBeInTheDocument();

        rerender(
            <LlmSummaryCompletedView
                billId={1}
                provisioning={provisioning({})}
                publishedSummary="The published summary."
                isBillPipelineRunning={false}
                runLoading={false}
                isRegenerating={true}
                abandoned={false}
                onConfirmRegenerate={vi.fn<() => void>()}
                modelOptions={[]}
                selectedModel=""
                onModelChange={() => {}}
            />,
        );

        expect(screen.queryByTestId("confirmation-dialog")).toBeNull();
    });

    // @lat: [[bill-summary-published-vs-draft-box-bug#publishedSummary prop notes]]
    it("tells the operator the draft is what gets replaced, not the published summary", () => {
        renderView();
        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));

        const dialog = screen.getByTestId("confirmation-dialog").textContent ?? "";
        expect(dialog).toMatch(/draft/i);
        expect(dialog).not.toMatch(/replace the existing summary/i);
    });
});

describe("LlmSummaryCompletedView composition", () => {
    // @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
    it("keeps the citation warning and leaves the testimony notices to the positions tab", () => {
        renderView();

        expect(screen.getByTestId("llm-citation-warning")).toBeInTheDocument();
        expect(screen.queryByTestId("llm-no-testimony")).toBeNull();
        expect(screen.queryByTestId("llm-testimony-attachment-warning")).toBeNull();
        expect(screen.queryByTestId("region-testimony-and-positions")).toBeNull();
        expect(screen.queryByTestId("textarea-supplemental-testimony")).toBeNull();
    });

    it("drops the citation warning when the server reports citations valid", () => {
        renderView({ citations_valid: true, invalid_citations: [] });

        expect(screen.queryByTestId("llm-citation-warning")).toBeNull();
    });
});
