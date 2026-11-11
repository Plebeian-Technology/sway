import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import BillCreatorPipelineStatusBadge from "app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge";

describe("BillCreatorPipelineStatusBadge — stale and empty-artifact branches", () => {
    it("renders 'Stale — bill amended' when stale=true", () => {
        render(<BillCreatorPipelineStatusBadge status="completed" stale={true} />);
        expect(screen.getByText(/Stale — bill amended/)).toBeInTheDocument();
    });

    it("renders 'Failed — no output' when error_message starts with 'empty_artifact:'", () => {
        render(
            <BillCreatorPipelineStatusBadge
                status="failed"
                errorMessage="empty_artifact: extract-text produced 0 files"
            />,
        );
        expect(screen.getByText(/Failed — no output/)).toBeInTheDocument();
    });

    it("falls back to generic failed badge when error_message has no 'empty_artifact:' sentinel", () => {
        render(<BillCreatorPipelineStatusBadge status="failed" errorMessage="boom" />);
        expect(screen.queryByText(/Failed — no output/)).not.toBeInTheDocument();
        // The plain "failed" badge still shows.
        expect(screen.getByText(/Failed/)).toBeInTheDocument();
    });

    it("stale branch precedes failed-empty branch when both signals coexist", () => {
        render(<BillCreatorPipelineStatusBadge status="failed" stale={true} errorMessage="empty_artifact: x" />);
        expect(screen.getByText(/Stale — bill amended/)).toBeInTheDocument();
        expect(screen.queryByText(/Failed — no output/)).not.toBeInTheDocument();
    });

    it("preserves existing 'Done' branch when no stale or empty-artifact signals are set", () => {
        render(<BillCreatorPipelineStatusBadge status="completed" />);
        expect(screen.getByText(/Done/)).toBeInTheDocument();
    });
});

describe("BillCreatorPipelineStatusBadge — an unrecognised status still draws a badge", () => {
    // @lat: [[bill-creator-pipeline-status-badge-fallback#How the status vocabulary is shaped, and why it isn't copied]]
    it("renders the raw status text instead of nothing", () => {
        render(
            <BillCreatorPipelineStatusBadge
                status={
                    "some_future_status" as unknown as Parameters<typeof BillCreatorPipelineStatusBadge>[0]["status"]
                }
            />,
        );
        expect(screen.getByTestId("pipeline-status-badge")).toBeInTheDocument();
        expect(screen.getByText("some_future_status")).toBeInTheDocument();
    });
});
