import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

const mockApiGet = jest.fn();
const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
        post: (...args: unknown[]) => mockApiPost(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

jest.mock("../../../../src/state/BootstrapContext", () => ({
    useBootstrap: () => ({
        bootstrap: { locale: { id: 7, name: "baltimore-maryland-united_states", city: "baltimore" } },
    }),
}));

import PipelineTab from "../../../../src/screens/admin/billCreator/tabs/PipelineTab";

const run = (id: number, status: string, overrides: Record<string, unknown> = {}) => ({
    id,
    status,
    kind: "single",
    error_message: null,
    bills_updated: null,
    completed_at: null,
    current_stage: "extract-text",
    pipeline_run_stages: [],
    ...overrides,
});

const recentRuns = [
    { id: 12, status: "cancelled", kind: "single", bill_external_id: "25-0001", created_at: null, completed_at: null },
    { id: 11, status: "failed", kind: "single", bill_external_id: "25-0001", created_at: null, completed_at: null },
];

const tabData = (pipelineRun: unknown) => ({
    bill: { id: 42, external_id: "25-0001", title: "A bill" },
    selected_stages: [],
    download_missing_assets: true,
    pipeline_preview: null,
    legislation_pipeline_run: pipelineRun,
    recent_pipeline_runs: recentRuns,
});

// @lat: [[mobile-bill-creator#Sections#The run selector section]]
describe("PipelineTab", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue({
            legislation_pipeline_run: run(11, "failed", { error_message: "boom" }),
            recent_pipeline_runs: recentRuns,
        });
        mockApiPost.mockResolvedValue({});
    });

    it("shows the picked run, then follows the latest run again", async () => {
        render(<PipelineTab billId={42} data={tabData(run(12, "cancelled"))} refresh={jest.fn(async () => {})} />);
        expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Cancelled");

        fireEvent.press(screen.getByTestId("admin-run-selector-toggle"));
        fireEvent.press(screen.getByTestId("admin-run-selector-option-11"));

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/pipeline?run_id=11", expect.anything()),
        );
        await waitFor(() => expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Failed"));
        expect(screen.getByTestId("admin-run-selector-current")).toHaveTextContent(/^Run #11/);

        fireEvent.press(screen.getByTestId("admin-run-selector-toggle"));
        fireEvent.press(screen.getByTestId("admin-run-selector-option-latest"));

        await waitFor(() => expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Cancelled"));
        expect(screen.getByTestId("admin-run-selector-current")).toHaveTextContent("Latest run (auto)");
    });

    it("returns to the latest run after resuming a picked run", async () => {
        const refresh = jest.fn(async () => {});
        render(<PipelineTab billId={42} data={tabData(run(12, "cancelled"))} refresh={refresh} />);
        fireEvent.press(screen.getByTestId("admin-run-selector-toggle"));
        fireEvent.press(screen.getByTestId("admin-run-selector-option-11"));
        await waitFor(() => expect(screen.getByTestId("admin-pipeline-resume")).toBeTruthy());

        fireEvent.press(screen.getByTestId("admin-pipeline-resume"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/legislation_pipeline_runs/11/resume", {}));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(screen.getByTestId("admin-run-selector-current")).toHaveTextContent("Latest run (auto)");
    });

    // @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
    it("keeps the cleanup counts while a run is picked and refetches the picked run after a sweep", async () => {
        const refresh = jest.fn(async () => {});
        mockApiPost.mockResolvedValue({ count: 2 });
        render(
            <PipelineTab
                billId={42}
                data={{ ...tabData(run(12, "cancelled")), stale_pipeline_run_count: 2 }}
                refresh={refresh}
            />,
        );
        fireEvent.press(screen.getByTestId("admin-run-selector-toggle"));
        fireEvent.press(screen.getByTestId("admin-run-selector-option-11"));
        await waitFor(() => expect(screen.getByTestId("admin-pipeline-status")).toHaveTextContent("Failed"));
        mockApiGet.mockClear();

        fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));
        fireEvent.press(screen.getByTestId("admin-pipeline-sweep-stale"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledWith("/bills/sweep_stale_pipeline_runs", {}));
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        await waitFor(() =>
            expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/pipeline?run_id=11", expect.anything()),
        );
    });
});
