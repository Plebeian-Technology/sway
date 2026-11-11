import { render, screen } from "@testing-library/react";
import LlmSummaryPipelineBusyNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPipelineBusyNotice";

// @lat: [[pipeline-busy-terminal-status-inversion#LlmSummaryPipelineBusyNotice.test.tsx notes]]
describe("LlmSummaryPipelineBusyNotice — the explanation slot carries the reason (C1-i6-WR-02)", () => {
    const notice = () => screen.getByTestId("bill-pipeline-refresh-status");
    const badge = () => screen.getByTestId("bill-pipeline-status-badge");
    const explanation = () => (notice().textContent ?? "").replace(badge().textContent ?? "", "").trim();

    it.each(["queued", "running"] as const)("says generation is unavailable while the run is %s", (status) => {
        render(<LlmSummaryPipelineBusyNotice billPipelineStatus={status} />);

        expect(explanation()).toMatch(/generation is unavailable/i);
    });

    it.each(["queued", "running"] as const)("does not just repeat the badge back at %s", (status) => {
        render(<LlmSummaryPipelineBusyNotice billPipelineStatus={status} />);

        expect(explanation()).not.toBe(badge().textContent?.trim());
    });

    // @lat: [[pipeline-busy-terminal-status-inversion#LlmSummaryPipelineBusyNotice.test.tsx notes]]
    it("does not tell the operator a queued run is already refreshing", () => {
        render(<LlmSummaryPipelineBusyNotice billPipelineStatus="queued" />);

        expect(badge().textContent).toMatch(/queued/i);
        expect(badge().textContent).not.toMatch(/refreshing/i);
    });

    it("still calls a running run a refresh", () => {
        render(<LlmSummaryPipelineBusyNotice billPipelineStatus="running" />);

        expect(badge().textContent).toMatch(/refreshing/i);
    });

    it.each(["completed", "failed", null] as const)("renders nothing for %s", (status) => {
        const { container } = render(<LlmSummaryPipelineBusyNotice billPipelineStatus={status} />);

        expect(container.firstChild).toBeNull();
    });
});
