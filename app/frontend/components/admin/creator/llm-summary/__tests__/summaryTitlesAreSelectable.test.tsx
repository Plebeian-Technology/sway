import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

// The completed branch mounts PasteSummaryDialog and LlmSummaryEditableSummary,
// and both read Inertia's page props and router.
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

const provisioning = (): IBillLlmProvisioning => ({
    generation_status: "completed",
    generation_error: null,
    llm_summary: "A summary.",
    llm_full_breakdown: "## Section 1\nWhat it does.",
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

// @lat: [[bill-creator-summary-tab#Why the section titles are headings rather than labels]]
describe("the summary tab's section titles are selectable text", () => {
    it("never applies select-none (an operator works the queue by copying text out)", () => {
        const { container } = renderView();

        expect(container.innerHTML).not.toMatch(/select-none/);
    });

    // Radix's Label cancels a mouse-down whose detail count is above one, so a
    // title inside one cannot be double-clicked to select it.
    it("renders no label element at all", () => {
        const { container } = renderView();

        expect(container.querySelectorAll("label")).toHaveLength(0);
    });

    it.each(["Public summary (editable — this is what users see)"])("reaches %s as a heading", (name) => {
        renderView();

        expect(screen.getByRole("heading", { name })).toBeTruthy();
    });
});
