// @lat: [[paste-summary-trigger-testid-uniqueness#Why pasteSummaryTriggerTestids.test.tsx renders both triggers together]]

import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    router: { post: vi.fn<(url: string, data?: unknown, config?: unknown) => void>() },
    usePage: () => ({ props: {} }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(message: unknown) => void>() }));

import LlmSummaryCompletedActions from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedActions";
import LlmSummaryPasteFallback from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPasteFallback";

describe("paste-summary trigger identifiers (C1-IN-05)", () => {
    it("gives each mount a distinct data-testid", () => {
        render(
            <>
                <LlmSummaryCompletedActions
                    stale={false}
                    isBillPipelineRunning={false}
                    runLoading={false}
                    isRegenerating={false}
                    modelOptions={[]}
                    selectedModel=""
                    onModelChange={() => {}}
                    onShowConfirmDialog={() => {}}
                    onPasteSummary={() => {}}
                />
                <LlmSummaryPasteFallback billId={1} />
            </>,
        );

        const ids = Array.from(document.querySelectorAll("[data-testid^='btn-paste-summary']")).map((el) =>
            el.getAttribute("data-testid"),
        );

        expect(ids).toHaveLength(2);
        expect(new Set(ids).size).toBe(2);
    });

    it("labels both of them identically for the operator — only the testid differs", () => {
        render(
            <>
                <LlmSummaryCompletedActions
                    stale={false}
                    isBillPipelineRunning={false}
                    runLoading={false}
                    isRegenerating={false}
                    modelOptions={[]}
                    selectedModel=""
                    onModelChange={() => {}}
                    onShowConfirmDialog={() => {}}
                    onPasteSummary={() => {}}
                />
                <LlmSummaryPasteFallback billId={1} />
            </>,
        );

        expect(screen.getAllByText("Paste summary JSON")).toHaveLength(2);
    });
});
