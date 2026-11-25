import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiDelete = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        delete: (...args: unknown[]) => mockApiDelete(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import PipelineCleanupSection from "../../../../src/components/admin/billCreator/PipelineCleanupSection";

const renderSection = (data: Record<string, unknown>, refresh = jest.fn(async () => {})) => {
    const view = render(<PipelineCleanupSection billId={42} data={data} refresh={refresh} />);
    return { refresh, view };
};

const runningRun = { id: 9, status: "running", kind: "single" };

// @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
describe("PipelineCleanupSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
        mockApiDelete.mockResolvedValue({});
    });

    it("shows nothing without an in-flight run or any stuck or orphan runs", () => {
        const { view } = renderSection({
            legislation_pipeline_run: { id: 9, status: "completed", kind: "single" },
            stale_pipeline_run_count: 0,
            orphan_pipeline_run_count: null,
        });
        expect(view.toJSON()).toBeNull();
    });

    describe("force fail", () => {
        it("shows for every in-flight status", () => {
            for (const status of ["queued", "running", "summarizing"]) {
                const { view } = renderSection({ legislation_pipeline_run: { id: 9, status, kind: "single" } });
                expect(screen.getByTestId("admin-pipeline-force-fail")).toBeTruthy();
                view.unmount();
            }
        });

        it("asks for the phrase and keeps confirm disabled until it matches exactly", () => {
            renderSection({ legislation_pipeline_run: runningRun });
            expect(screen.queryByTestId("admin-pipeline-force-fail-phrase-input")).toBeNull();

            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail"));
            const confirm = screen.getByTestId("admin-pipeline-force-fail-confirm");
            expect(confirm.props.accessibilityState?.disabled).toBe(true);

            fireEvent.changeText(screen.getByTestId("admin-pipeline-force-fail-phrase-input"), "force fai");
            expect(screen.getByTestId("admin-pipeline-force-fail-confirm").props.accessibilityState?.disabled).toBe(
                true,
            );

            fireEvent.changeText(screen.getByTestId("admin-pipeline-force-fail-phrase-input"), "force fail");
            expect(screen.getByTestId("admin-pipeline-force-fail-confirm").props.accessibilityState?.disabled).toBe(
                false,
            );
        });

        it("sends the typed phrase, refreshes and closes the panel", async () => {
            const { refresh } = renderSection({ legislation_pipeline_run: runningRun });

            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail"));
            fireEvent.changeText(screen.getByTestId("admin-pipeline-force-fail-phrase-input"), "force fail");
            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail-confirm"));

            await waitFor(() =>
                expect(mockApiPost).toHaveBeenCalledWith("/pipeline_runs/9/force_fail", {
                    confirm_phrase: "force fail",
                }),
            );
            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(screen.queryByTestId("admin-pipeline-force-fail-phrase-input")).toBeNull();
        });

        it("clears the phrase when the admin cancels", () => {
            renderSection({ legislation_pipeline_run: runningRun });

            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail"));
            fireEvent.changeText(screen.getByTestId("admin-pipeline-force-fail-phrase-input"), "force fail");
            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail-cancel"));
            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail"));

            expect(screen.getByTestId("admin-pipeline-force-fail-phrase-input").props.value).toBe("");
        });

        it("shows the server's reason, keeps the panel open and does not refresh", async () => {
            mockApiPost.mockRejectedValue(
                new ApiRequestError(
                    "validation_failed",
                    "Validation failed.",
                    { pipeline: "Run #9 is not in-flight (status: completed)" },
                    422,
                ),
            );
            const { refresh } = renderSection({ legislation_pipeline_run: runningRun });

            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail"));
            fireEvent.changeText(screen.getByTestId("admin-pipeline-force-fail-phrase-input"), "force fail");
            fireEvent.press(screen.getByTestId("admin-pipeline-force-fail-confirm"));

            expect(await screen.findByTestId("admin-pipeline-force-fail-error")).toHaveTextContent(
                "Run #9 is not in-flight (status: completed)",
            );
            expect(screen.getByTestId("admin-pipeline-force-fail-phrase-input")).toBeTruthy();
            expect(refresh).not.toHaveBeenCalled();
        });
    });

    describe("stuck runs", () => {
        it("is hidden when no run is stuck", () => {
            renderSection({ stale_pipeline_run_count: 0, orphan_pipeline_run_count: 1 });
            expect(screen.queryByTestId("admin-pipeline-sweep-stale")).toBeNull();
        });

        it("takes two taps, posts to the sweep endpoint and shows the count", async () => {
            const { refresh } = renderSection({ stale_pipeline_run_count: 3 });
            mockApiPost.mockResolvedValue({ count: 3 });

            expect(screen.getByText("Remove 3 stuck runs")).toBeTruthy();
            fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));
            expect(mockApiPost).not.toHaveBeenCalled();
            expect(screen.getByText("Tap again to mark 3 stuck runs as failed")).toBeTruthy();

            fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));

            await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/sweep_stale_pipeline_runs", {}));
            expect(await screen.findByTestId("admin-pipeline-sweep-stale-result")).toHaveTextContent(
                "Cleared 3 stuck pipeline runs.",
            );
            expect(refresh).toHaveBeenCalledTimes(1);
        });

        it("says run in the singular for one run", async () => {
            renderSection({ stale_pipeline_run_count: 1 });
            mockApiPost.mockResolvedValue({ count: 1 });

            expect(screen.getByText("Remove 1 stuck run")).toBeTruthy();
            fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));
            fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));

            expect(await screen.findByTestId("admin-pipeline-sweep-stale-result")).toHaveTextContent(
                "Cleared 1 stuck pipeline run.",
            );
        });

        it("shows the server's message and does not refresh when the sweep fails", async () => {
            mockApiPost.mockRejectedValue(new ApiRequestError("server_error", "Sweep failed.", undefined, 500));
            const { refresh } = renderSection({ stale_pipeline_run_count: 2 });

            fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));
            fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));

            expect(await screen.findByTestId("admin-pipeline-sweep-stale-error")).toHaveTextContent("Sweep failed.");
            expect(refresh).not.toHaveBeenCalled();
        });
    });

    describe("orphan runs", () => {
        it("is hidden when there are no orphan runs", () => {
            renderSection({ stale_pipeline_run_count: 1, orphan_pipeline_run_count: 0 });
            expect(screen.queryByTestId("admin-pipeline-delete-orphans")).toBeNull();
        });

        it("takes two taps, deletes through the orphans endpoint and shows the count", async () => {
            mockApiDelete.mockResolvedValue({ deleted_ids: [4, 5], count: 2 });
            const { refresh } = renderSection({ orphan_pipeline_run_count: 2 });

            expect(screen.getByText("Delete 2 orphan runs")).toBeTruthy();
            fireEvent.press(screen.getByTestId("admin-pipeline-delete-orphans"));
            expect(mockApiDelete).not.toHaveBeenCalled();
            expect(screen.getByText("Tap again to delete 2 orphan runs")).toBeTruthy();

            fireEvent.press(screen.getByTestId("admin-pipeline-delete-orphans"));

            await waitFor(() => expect(mockApiDelete).toHaveBeenCalledWith("/pipeline_runs/orphans"));
            expect(await screen.findByTestId("admin-pipeline-delete-orphans-result")).toHaveTextContent(
                "Removed 2 orphan runs.",
            );
            expect(refresh).toHaveBeenCalledTimes(1);
        });

        it("says so when nothing was left to remove", async () => {
            mockApiDelete.mockResolvedValue({ deleted_ids: [], count: 0 });
            renderSection({ orphan_pipeline_run_count: 1 });

            fireEvent.press(screen.getByTestId("admin-pipeline-delete-orphans"));
            fireEvent.press(screen.getByTestId("admin-pipeline-delete-orphans"));

            expect(await screen.findByTestId("admin-pipeline-delete-orphans-result")).toHaveTextContent(
                "No orphan runs to remove.",
            );
        });

        it("keeps the result on screen after the refreshed counts drop to zero", async () => {
            mockApiDelete.mockResolvedValue({ deleted_ids: [4], count: 1 });
            const view = render(
                <PipelineCleanupSection billId={42} data={{ orphan_pipeline_run_count: 1 }} refresh={jest.fn()} />,
            );

            fireEvent.press(screen.getByTestId("admin-pipeline-delete-orphans"));
            fireEvent.press(screen.getByTestId("admin-pipeline-delete-orphans"));
            await screen.findByTestId("admin-pipeline-delete-orphans-result");
            view.rerender(
                <PipelineCleanupSection billId={42} data={{ orphan_pipeline_run_count: 0 }} refresh={jest.fn()} />,
            );

            expect(screen.getByTestId("admin-pipeline-delete-orphans-result")).toHaveTextContent(
                "Removed 1 orphan run.",
            );
            expect(screen.queryByTestId("admin-pipeline-delete-orphans")).toBeNull();
        });
    });
});
