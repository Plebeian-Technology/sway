import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { post: (...args: unknown[]) => mockApiPost(...args) },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import PipelineRunActionsSection from "../../../../src/components/admin/billCreator/PipelineRunActionsSection";

const failedRun = (overrides: Record<string, unknown> = {}) => ({
    id: 9,
    status: "failed",
    kind: "single",
    current_stage: "extract-text",
    pipeline_run_stages: [],
    ...overrides,
});

const renderSection = (pipelineRun: unknown, refresh = jest.fn(async () => {})) => {
    const view = render(
        <PipelineRunActionsSection billId={42} data={{ legislation_pipeline_run: pipelineRun }} refresh={refresh} />,
    );
    return { refresh, view };
};

// @lat: [[mobile-bill-creator#Sections#The pipeline run controls section]]
describe("PipelineRunActionsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
    });

    it("resumes the failed run and refreshes the tab", async () => {
        const { refresh } = renderSection(failedRun());

        fireEvent.press(screen.getByTestId("admin-pipeline-resume"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/legislation_pipeline_runs/9/resume", {}));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("restarts the whole run and refreshes the tab", async () => {
        const { refresh } = renderSection(failedRun());

        fireEvent.press(screen.getByTestId("admin-pipeline-restart"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/legislation_pipeline_runs/9/restart", {}));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(screen.getByText("Restart entire run")).toBeTruthy();
    });

    it("names the failed stage on Resume from the failed stage row", () => {
        renderSection(
            failedRun({
                pipeline_run_stages: [
                    { stage_name: "fetch-bills", status: "succeeded", position: 1, finished_at: null },
                    { stage_name: "extract-text", status: "failed", position: 2, finished_at: null },
                ],
            }),
        );
        expect(screen.getByText("Resume from stage 2")).toBeTruthy();
    });

    it("counts the current stage's place in the stage list when no stage row failed", () => {
        renderSection(failedRun({ current_stage: "parse-sections" }));
        expect(screen.getByText("Resume from stage 4")).toBeTruthy();
    });

    it("reads Resume alone when no stage is known", () => {
        renderSection(failedRun({ current_stage: null }));
        expect(screen.getByText("Resume")).toBeTruthy();
    });

    it("shows nothing unless the run is a failed single-bill run", () => {
        for (const run of [failedRun({ kind: "all_bills" }), failedRun({ status: "cancelled" }), null]) {
            const { view } = renderSection(run);
            expect(view.toJSON()).toBeNull();
            view.unmount();
        }
    });

    it("shows the server's reason for a refusal and does not refresh", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("validation_failed", "Validation failed.", { pipeline: "Run cannot be resumed." }, 422),
        );
        const { refresh } = renderSection(failedRun());

        fireEvent.press(screen.getByTestId("admin-pipeline-resume"));

        expect(await screen.findByTestId("admin-pipeline-run-action-error")).toHaveTextContent(
            "Run cannot be resumed.",
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows the message of a run already in flight", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("duplicate_run", "Pipeline already running (run #12)", undefined, 409),
        );
        renderSection(failedRun());

        fireEvent.press(screen.getByTestId("admin-pipeline-restart"));

        expect(await screen.findByTestId("admin-pipeline-run-action-error")).toHaveTextContent(
            "Pipeline already running (run #12)",
        );
    });
});
