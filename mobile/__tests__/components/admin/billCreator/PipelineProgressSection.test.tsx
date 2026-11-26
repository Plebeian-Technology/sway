import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiDelete = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: { delete: (...args: unknown[]) => mockApiDelete(...args) },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import PipelineProgressSection from "../../../../src/components/admin/billCreator/PipelineProgressSection";

const run = (overrides: Record<string, unknown> = {}) => ({
    id: 9,
    status: "extracting_text",
    kind: "single",
    error_message: null,
    bills_updated: null,
    completed_at: null,
    abandoned: false,
    pipeline_run_stages: [],
    ...overrides,
});

const tabData = (pipelineRun: unknown, bill: Record<string, unknown> = {}) => ({
    bill: { id: 42, external_id: "25-0001", title: "A bill", ...bill },
    legislation_pipeline_run: pipelineRun,
});

const renderView = (data: ReturnType<typeof tabData>, billId: number | null = 42) => {
    const view = render(<PipelineProgressSection billId={billId} data={data} refresh={jest.fn()} />);
    return { view };
};

const renderSection = (data: ReturnType<typeof tabData>, billId: number | null = 42) => {
    const refresh = jest.fn(async () => {});
    const view = render(<PipelineProgressSection billId={billId} data={data} refresh={refresh} />);
    return { refresh, rerender: view.rerender };
};

// @lat: [[mobile-bill-creator#Sections#The pipeline progress section]]
describe("PipelineProgressSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiDelete.mockResolvedValue({});
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    it("shows an in-flight run's stage, then its finished state, and stops polling", () => {
        const { refresh, rerender } = renderSection(tabData(run()));

        expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Extracting text");
        expect(screen.getByTestId("admin-pipeline-progress-bar")).toBeTruthy();
        jest.advanceTimersByTime(5000);
        expect(refresh).toHaveBeenCalledTimes(1);

        rerender(
            <PipelineProgressSection
                billId={42}
                data={tabData(run({ status: "completed", bills_updated: 3 }))}
                refresh={refresh}
            />,
        );

        expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Done");
        expect(screen.getByTestId("admin-pipeline-success-alert")).toHaveTextContent(
            "Pipeline complete3 bill(s) updated.",
        );
        expect(screen.queryByTestId("admin-pipeline-progress-bar")).toBeNull();
        jest.advanceTimersByTime(20000);
        expect(refresh).toHaveBeenCalledTimes(1);
    });

    it("keeps polling while the bill's own refresh runs after its run has finished", () => {
        const { refresh } = renderSection(
            tabData(run({ status: "failed" }), { bill_pipeline_refresh: { status: "running" } }),
        );

        jest.advanceTimersByTime(10000);
        expect(refresh).toHaveBeenCalledTimes(2);
    });

    it("says so when there is no run yet and does not poll", () => {
        const { refresh } = renderSection(tabData(null));

        expect(screen.getByTestId("admin-pipeline-progress")).toHaveTextContent(
            "No pipeline run yet. Select stages and click Run pipeline to start ingestion.",
        );
        jest.advanceTimersByTime(20000);
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows a running run's bill, counts, time left, queue and errors", () => {
        renderSection(
            tabData(
                run({
                    status: "running",
                    phase: "downloading",
                    processed: 2,
                    total: 8,
                    current_bill_external_id: "25-0003",
                    eta_seconds: 125,
                    queued: ["25-0004", "25-0005"],
                    errors: [{ external_id: "25-0002", phase: "extracting", message: "no text", at: "" }],
                }),
            ),
        );

        expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Running");
        expect(screen.getByTestId("admin-pipeline-error-count")).toHaveTextContent("1 bill error(s)");
        expect(screen.getByTestId("admin-pipeline-phase")).toHaveTextContent("Downloading PDFs");
        expect(screen.getByTestId("admin-pipeline-progress-bar-fill").props.style).toEqual({ width: "25%" });
        expect(screen.getByTestId("admin-pipeline-current-bill")).toHaveTextContent("25-0003");
        expect(screen.getByTestId("admin-pipeline-eta")).toHaveTextContent("~2m 5s remaining");
        expect(screen.getByText("2 / 8 bills")).toBeTruthy();

        expect(screen.queryByTestId("admin-pipeline-queued-list")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-pipeline-queue-toggle"));
        expect(screen.getByTestId("admin-pipeline-queued-list")).toHaveTextContent("25-000425-0005");

        expect(screen.queryByTestId("admin-pipeline-errors-list")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-pipeline-errors-toggle"));
        expect(screen.getByTestId("admin-pipeline-errors-list")).toHaveTextContent("25-0002 — extracting: no text");
    });

    it("tells an abandoned run apart and hides its progress bar", () => {
        renderSection(tabData(run({ status: "running", abandoned: true })));

        expect(screen.getByTestId("admin-pipeline-abandoned-notice")).toBeTruthy();
        expect(screen.queryByTestId("admin-pipeline-progress-bar")).toBeNull();
    });

    it("shows the succeeded, partial and cancelled alerts", () => {
        const { refresh, rerender } = renderSection(tabData(run({ status: "succeeded" })));
        expect(screen.getByTestId("admin-pipeline-succeeded-alert")).toHaveTextContent(
            "Run succeededAll bills processed successfully.",
        );

        rerender(<PipelineProgressSection billId={42} data={tabData(run({ status: "partial" }))} refresh={refresh} />);
        expect(screen.getByTestId("admin-pipeline-partial-alert")).toHaveTextContent("Run completed with failures", {
            exact: false,
        });

        rerender(
            <PipelineProgressSection
                billId={42}
                data={tabData(
                    run({ status: "cancelled", processed: 3, total: 9, completed_at: "2026-11-24T11:00:00Z" }),
                )}
                refresh={refresh}
            />,
        );
        expect(screen.getByTestId("admin-pipeline-cancelled-alert")).toHaveTextContent(
            "Run cancelledCancelled at November 24, 2026 at 11:00 AM. 3 of 9 bills processed before cancel.",
        );
    });

    it("shows a failed single-bill run's stages, reason, remedy and time", () => {
        renderSection(
            tabData(
                run({
                    status: "failed",
                    phase: "extracting",
                    error_message: "OCR crashed",
                    completed_at: "2026-11-24T11:00:00Z",
                    pipeline_run_stages: [
                        { stage_name: "fetch-bills", status: "succeeded", position: 1, finished_at: null },
                        {
                            stage_name: "extract-text",
                            status: "failed",
                            position: 2,
                            finished_at: "2026-11-24T11:00:00Z",
                        },
                    ],
                }),
            ),
        );

        expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Failed");
        expect(screen.getByTestId("admin-pipeline-cached-stages")).toHaveTextContent(
            "1.fetch-billssucceeded2.extract-textfailedNovember 24, 2026 at 11:00 AM",
        );
        expect(screen.getByTestId("admin-pipeline-error-alert")).toHaveTextContent(
            "Pipeline failedDuring Extracting text: OCR crashed — use Resume above to try the failed stage again, or Restart to run it from the beginning.",
            { exact: false },
        );
        expect(screen.getByTestId("admin-pipeline-failure-timing")).toHaveTextContent(
            "Failed 1h ago — November 24, 2026 at 11:00 AM",
        );
    });

    it("names Run pipeline as the remedy for a failed run over every bill", () => {
        const failed = run({ status: "failed", kind: "all_bills", error_message: null });
        const { refresh, rerender } = renderSection(tabData(failed));

        expect(screen.queryByTestId("admin-pipeline-cached-stages")).toBeNull();
        expect(screen.getByTestId("admin-pipeline-error-alert")).toHaveTextContent(
            "Unknown error — the bill picker above holds one bill, so Run pipeline starts a run for that bill alone.",
            { exact: false },
        );

        rerender(<PipelineProgressSection billId={null} data={tabData(failed)} refresh={refresh} />);
        expect(screen.getByTestId("admin-pipeline-error-alert")).toHaveTextContent(
            "Unknown error — pick the stages above and click Run pipeline, which starts a run over every bill.",
            { exact: false },
        );
    });

    it("labels a failure with no output", () => {
        renderSection(tabData(run({ status: "failed", error_message: "empty_artifact: nothing extracted" })));

        expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Failed — no output");
    });
    describe("cancelling a run", () => {
        it("asks to tap again, then cancels the run and refreshes the tab", async () => {
            const { refresh } = renderSection(tabData(run()));

            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));
            expect(screen.getByText("Tap again to cancel")).toBeTruthy();
            expect(mockApiDelete).not.toHaveBeenCalled();

            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));

            await waitFor(() => expect(mockApiDelete).toHaveBeenCalledWith("/bills/legislation_pipeline_runs/9"));
            await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
            expect(screen.getByText("Cancel run")).toBeTruthy();
        });

        it("forgets the first tap after three seconds", () => {
            renderSection(tabData(run()));

            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));
            act(() => {
                jest.advanceTimersByTime(3000);
            });

            expect(screen.getByText("Cancel run")).toBeTruthy();
            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));
            expect(mockApiDelete).not.toHaveBeenCalled();
        });

        it("offers Clear this run for an abandoned run", async () => {
            renderSection(tabData(run({ status: "running", abandoned: true })));

            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));
            expect(screen.getByText("Tap again to clear")).toBeTruthy();
            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));

            await waitFor(() => expect(mockApiDelete).toHaveBeenCalledWith("/bills/legislation_pipeline_runs/9"));
        });

        it("names the button Cancel run before the first tap, and Clear this run when abandoned", () => {
            const { rerender } = renderSection(tabData(run({ status: "queued" })));
            expect(screen.getByText("Cancel run")).toBeTruthy();

            rerender(
                <PipelineProgressSection
                    billId={42}
                    data={tabData(run({ status: "queued", abandoned: true }))}
                    refresh={jest.fn()}
                />,
            );
            expect(screen.getByText("Clear this run")).toBeTruthy();
        });

        it("offers no button for a finished run", () => {
            for (const status of ["completed", "succeeded", "partial", "failed", "cancelled"]) {
                const { view } = renderView(tabData(run({ status })));
                expect(screen.queryByTestId("admin-pipeline-cancel")).toBeNull();
                view.unmount();
            }
        });

        it("shows the server's reason when the run cannot be cancelled and does not refresh", async () => {
            mockApiDelete.mockRejectedValue(
                new ApiRequestError("validation_failed", "Cannot cancel run in status=completed", undefined, 422),
            );
            const { refresh } = renderSection(tabData(run()));

            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));
            fireEvent.press(screen.getByTestId("admin-pipeline-cancel"));

            expect(await screen.findByTestId("admin-pipeline-cancel-error")).toHaveTextContent(
                "Cannot cancel run in status=completed",
            );
            expect(refresh).not.toHaveBeenCalled();
        });
    });
});
