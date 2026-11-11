import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

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
import { PUBLIC_SUMMARY_TITLE_ID } from "app/frontend/components/admin/creator/llm-summary/summaryTitleIds";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

const PUBLIC_SUMMARY_TITLE = "Public summary (editable — this is what users see)";

const provisioning = (): IBillLlmProvisioning => ({
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
    has_testimony: true,
    testimony_attachments: [],
    citations_valid: true,
    invalid_citations: [],
});

const renderView = () =>
    render(
        <LlmSummaryCompletedView
            billId={1}
            provisioning={provisioning()}
            publishedSummary="The published summary."
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

// @lat: [[bill-creator-summary-tab#Where the summary stops and the positions start]]
describe("the summary tab's heading hierarchy", () => {
    it("opens each section at level 3 and each sub-section at level 4", () => {
        renderView();

        const levels = screen.getAllByRole("heading").map((el) => Number(el.tagName.slice(1)));

        expect(levels).toEqual([3]);
    });

    it("names the public summary box with its own heading, character for character", () => {
        renderView();

        expect(screen.getByTestId("textarea-llm-summary").getAttribute("aria-labelledby")).toBe(
            PUBLIC_SUMMARY_TITLE_ID,
        );
        expect(document.getElementById(PUBLIC_SUMMARY_TITLE_ID)?.textContent?.replace(/\s+/g, " ").trim()).toBe(
            PUBLIC_SUMMARY_TITLE,
        );
    });

    it("leaves the accessible name of the box unchanged by the move off Label", () => {
        renderView();

        // The panel region names itself with the same heading, so the lookup
        // names the element under test.
        expect(screen.getByLabelText(PUBLIC_SUMMARY_TITLE, { selector: "textarea" })).toBe(
            screen.getByTestId("textarea-llm-summary"),
        );
    });
});
