import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

// @lat: [[operator-paste-provenance-test-notes#File scope]]
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

import BillCreatorLlmSummaryStatus from "app/frontend/components/admin/creator/llm-summary/BillCreatorLlmSummaryStatus";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[operator-paste-provenance-test-notes#Why this scenario is tested (the destructive-unconfirmed-click bug)]]
const pastedProvisioning: IBillLlmProvisioning = {
    generation_status: "completed",
    generation_error: null,
    llm_summary: "Hand-written by the operator over an afternoon.",
    llm_full_breakdown: null,
    supplemental_testimony: null,
    draft_org_positions: [],
    stale: true,
    reclaimable: false,
    // @lat: [[operator-paste-provenance-test-notes#Why one fixture disagrees the two paste columns]]
    paste_owns_summary_run: true,
    stale_change_kind: "pipeline_data" as const,
    stale_change_at: "2026-07-20T00:00:00Z",
    llm_generated_at: "2026-07-18T00:00:00Z",
    llm_provider: "operator_paste",
    has_testimony: true,
    testimony_attachments: null,
    citations_valid: null,
    invalid_citations: null,
};

const generatedProvisioning: IBillLlmProvisioning = {
    ...pastedProvisioning,
    llm_summary: "Bought from the model.",
    llm_provider: "claude",
    // @lat: [[operator-paste-provenance-test-notes#Why one fixture disagrees the two paste columns]]
    paste_owns_summary_run: false,
};

// @lat: [[operator-paste-provenance-test-notes#Why one fixture disagrees the two paste columns]]
const pastedThenReleasedProvisioning: IBillLlmProvisioning = {
    ...pastedProvisioning,
    generation_status: "skipped",
    paste_owns_summary_run: false,
};

const renderStatus = (
    provisioning: IBillLlmProvisioning,
    overrides: Partial<React.ComponentProps<typeof BillCreatorLlmSummaryStatus>> = {},
) => {
    const onRegenerate = vi.fn<() => void>();
    render(
        <BillCreatorLlmSummaryStatus
            billId={42}
            provisioning={provisioning}
            publishedSummary="The published summary."
            billPipelineStatus={null}
            isBillPipelineRunning={false}
            isRegenerating={false}
            regenLoading={false}
            onRegenerate={onRegenerate}
            onGenerate={vi.fn<() => void>()}
            modelOptions={[]}
            selectedModel=""
            onModelChange={() => {}}
            {...overrides}
        />,
    );
    return { onRegenerate };
};

describe("operator-paste provenance on a permanently stale row (C1-i6-CR-01)", () => {
    it("tells the operator the summary was hand-written", () => {
        renderStatus(pastedProvisioning);

        expect(screen.getByTestId("llm-operator-paste-chip")).toHaveTextContent(/operator-pasted/i);
    });

    it("does not claim a model-generated summary was hand-written", () => {
        renderStatus(generatedProvisioning);

        expect(screen.queryByTestId("llm-operator-paste-chip")).not.toBeInTheDocument();
    });

    // @lat: [[operator-paste-provenance-test-notes#Why one fixture disagrees the two paste columns]]
    it("still shows the paste chip on a row whose pasted body outlived a released regeneration", () => {
        renderStatus(pastedThenReleasedProvisioning);

        expect(screen.getByTestId("llm-operator-paste-chip")).toHaveTextContent(/operator-pasted/i);
    });

    // @lat: [[operator-paste-provenance-test-notes#Why the destructive-click example matters]]
    it("does not fire the destructive POST on the first click", () => {
        const { onRegenerate } = renderStatus(pastedProvisioning);

        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));

        expect(onRegenerate).not.toHaveBeenCalled();
        expect(screen.getByTestId("confirmation-dialog")).toBeInTheDocument();
    });

    it("warns that the body is hand-written and cannot be recovered", () => {
        renderStatus(pastedProvisioning);

        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));

        expect(screen.getByTestId("confirmation-dialog")).toHaveTextContent(/hand-written/i);
        expect(screen.getByTestId("confirmation-dialog")).toHaveTextContent(/cannot be recovered/i);
    });

    it("regenerates once the operator confirms", () => {
        const { onRegenerate } = renderStatus(pastedProvisioning);

        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(onRegenerate).toHaveBeenCalledTimes(1);
    });

    it("abandons the regenerate when the operator cancels", () => {
        const { onRegenerate } = renderStatus(pastedProvisioning);

        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-cancel"));

        expect(onRegenerate).not.toHaveBeenCalled();
    });

    // @lat: [[operator-paste-provenance-test-notes#Model-generated stale rows get different confirmation copy]]
    it("still confirms for a model-generated stale summary, without the paste copy", () => {
        const { onRegenerate } = renderStatus(generatedProvisioning);

        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));

        expect(onRegenerate).not.toHaveBeenCalled();
        expect(screen.getByTestId("confirmation-dialog")).not.toHaveTextContent(/hand-written/i);
    });

    // @lat: [[operator-paste-provenance-test-notes#The pipeline-ignoring generate button]]
    it("disables the stale CTA while the bill pipeline is running", () => {
        renderStatus(pastedProvisioning, { isBillPipelineRunning: true, billPipelineStatus: "running" });

        expect(screen.getByTestId("btn-regenerate-from-latest-data")).toBeDisabled();
    });
});
