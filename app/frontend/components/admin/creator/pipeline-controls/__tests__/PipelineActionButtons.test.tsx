import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import PipelineActionButtons from "../PipelineActionButtons";

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ city: "baltimore" }, vi.fn<() => void>()],
}));

// @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]]
describe("PipelineActionButtons", () => {
    const props = {
        runDisabled: false,
        runDisabledReason: null as string | null,
        isRunning: false,
        pickedBillId: "",
        staleCount: 0,
        orphanCount: 0,
        onRun: () => {},
        onSweepStale: () => {},
        onDeleteOrphans: () => {},
    };

    const runButton = () => screen.getByTestId("btn-run-pipeline");
    const spinner = () => screen.queryByTestId("pipeline-run-spinner");

    it("describes the disabled run button with the reason it is off", () => {
        render(<PipelineActionButtons {...props} runDisabled runDisabledReason="Pick at least one stage to run." />);

        const notice = screen.getByTestId("run-pipeline-disabled-reason");
        expect(notice).toHaveTextContent("Pick at least one stage to run.");

        // @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]]
        expect(runButton()).toBeDisabled();
        expect(runButton().getAttribute("aria-describedby")).toBe(notice.id);
        expect(notice.id).not.toBe("");
    });

    it("shows whichever reason it is given, not one fixed sentence", () => {
        render(
            <PipelineActionButtons
                {...props}
                runDisabled
                runDisabledReason="A run is in flight. Cancel it before starting another."
            />,
        );

        expect(screen.getByTestId("run-pipeline-disabled-reason")).toHaveTextContent(
            "A run is in flight. Cancel it before starting another.",
        );
    });

    it("renders no notice and points at nothing when the button works", () => {
        render(<PipelineActionButtons {...props} />);

        expect(screen.queryByTestId("run-pipeline-disabled-reason")).toBeNull();
        expect(runButton()).toBeEnabled();
        expect(runButton().getAttribute("aria-describedby")).toBeNull();
    });

    it("shows a spinner beside the run button while a run is in flight", () => {
        render(
            <PipelineActionButtons
                {...props}
                isRunning
                runDisabled
                runDisabledReason="A run is in flight. Cancel it before starting another."
            />,
        );

        const icon = spinner();
        expect(icon).toBeInTheDocument();
        expect(icon).toHaveClass("animate-spin");
        expect(icon).toHaveAttribute("aria-label", "Pipeline run in progress");
    });

    it("does not show a spinner when disabled only because nothing is selected", () => {
        render(<PipelineActionButtons {...props} runDisabled runDisabledReason="Pick at least one stage to run." />);

        expect(spinner()).toBeNull();
    });

    it("does not show a spinner when the button is enabled and idle", () => {
        render(<PipelineActionButtons {...props} />);

        expect(spinner()).toBeNull();
    });
});
