import { render, screen } from "@testing-library/react";
import LlmSummaryGenerateBranch from "app/frontend/components/admin/creator/llm-summary/LlmSummaryGenerateBranch";

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button {...props}>{children}</button>
    ),
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, ...props }: React.HTMLAttributes<HTMLSpanElement>) => <span {...props}>{children}</span>,
}));

const baseProps = {
    // Only the failed branch's paste fallback reads this, and every example
    // here is a never-generated row. It is supplied so the props type-check.
    billId: 42,
    status: null,
    generationError: null,
    onGenerate: vi.fn<() => void>(),
    // @lat: [[bill-creator-generate-branch-layout#What LlmSummaryGenerateBranch.test.tsx tests]]
    isBillPipelineRunning: false,
    isRegenerating: false,
    // @lat: [[bill-creator-generate-branch-layout#Why the abandoned notice can assume "never started" here]]
    abandoned: false,
    hasTestimony: false,
};

describe("LlmSummaryGenerateBranch — the per-run model picker", () => {
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    const options = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5" },
        { id: "claude-opus-5-5", label: "Opus 5.5" },
    ];

    it("renders the picker beside Generate summary", () => {
        render(
            <LlmSummaryGenerateBranch
                {...baseProps}
                modelOptions={options}
                selectedModel="claude-opus-5-5"
                onModelChange={vi.fn<(model: string) => void>()}
            />,
        );

        expect(screen.getByTestId("select-summary-model").textContent).toContain("Opus 5.5");
    });

    it("renders no picker when the server offered no models", () => {
        render(<LlmSummaryGenerateBranch {...baseProps} />);

        expect(screen.queryByTestId("select-summary-model")).toBeNull();
    });
});
