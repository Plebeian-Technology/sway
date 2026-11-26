import React from "react";
import { act, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import PipelineRunsScreen from "../../../src/screens/admin/PipelineRunsScreen";

const NOW = Date.parse("2026-11-18T12:00:00Z");

const failedRun = {
    id: 41,
    status: "failed",
    kind: "single",
    bill_id: 7,
    bill_external_id: "26-0001",
    remote_run_id: "remote-41",
    started_at: "2026-11-18T11:00:00Z",
    completed_at: "2026-11-18T11:30:00Z",
    current_stage: "summarizing",
    bills_total: 3,
    bills_succeeded: 1,
    bills_failed: 2,
    failing_stage: "parsing_sections",
};

const queuedRun = {
    id: 42,
    status: "queued",
    kind: "all_bills",
    bill_id: null,
    bill_external_id: null,
    remote_run_id: null,
    started_at: null,
    completed_at: null,
    current_stage: null,
    bills_total: 0,
    bills_succeeded: 0,
    bills_failed: 0,
    failing_stage: null,
};

// @lat: [[mobile-admin-area#The pipeline runs screen]]
describe("PipelineRunsScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        jest.spyOn(Date, "now").mockReturnValue(NOW);
    });

    afterEach(() => {
        jest.restoreAllMocks();
    });

    it("shows each run with its status, kind, bill, times, bill counts and failing stage", async () => {
        mockApiGet.mockResolvedValue({ runs: [failedRun, queuedRun] });
        render(<PipelineRunsScreen />);

        expect(await screen.findByText("Run #41")).toBeTruthy();
        expect(screen.getByText("failed")).toBeTruthy();
        expect(screen.getByText("single")).toBeTruthy();
        expect(screen.getByText("26-0001")).toBeTruthy();
        expect(screen.getByText("1h ago (2026-11-18T11:00:00Z)")).toBeTruthy();
        expect(screen.getByText("30m ago (2026-11-18T11:30:00Z)")).toBeTruthy();
        expect(screen.getByText("1 / 2 / 3")).toBeTruthy();
        expect(screen.getByText("parsing_sections")).toBeTruthy();

        expect(screen.getByText("Run #42")).toBeTruthy();
        expect(screen.getByText("queued")).toBeTruthy();
        expect(screen.getByText("all bills")).toBeTruthy();
        expect(screen.getByText("0 / 0 / 0")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/pipeline_runs", expect.anything());
    });

    it("shows a dash for a bill, times and failing stage a run does not have", async () => {
        mockApiGet.mockResolvedValue({ runs: [queuedRun] });
        render(<PipelineRunsScreen />);

        await screen.findByText("Run #42");
        expect(screen.getAllByText("—")).toHaveLength(4);
    });

    it("shows an empty state when there are no runs", async () => {
        mockApiGet.mockResolvedValue({ runs: [] });
        render(<PipelineRunsScreen />);

        expect(await screen.findByText("No pipeline runs yet.")).toBeTruthy();
    });

    it("refetches on pull to refresh", async () => {
        mockApiGet.mockResolvedValue({ runs: [failedRun] });
        render(<PipelineRunsScreen />);
        await screen.findByText("Run #41");

        mockApiGet.mockResolvedValue({ runs: [queuedRun] });
        await act(async () => {
            screen.getByTestId("admin-pipeline-runs-screen").props.refreshControl.props.onRefresh();
        });

        expect(await screen.findByText("Run #42")).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledTimes(2);
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<PipelineRunsScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});
