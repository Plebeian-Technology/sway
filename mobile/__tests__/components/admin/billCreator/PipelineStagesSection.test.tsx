import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

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

import PipelineStagesSection from "../../../../src/components/admin/billCreator/PipelineStagesSection";

const DEFAULT_STAGES = [
    "fetch-bills",
    "fetch-law",
    "extract-text",
    "parse-sections",
    "generate-diffs",
    "fetch-hearings",
    "clean-testimony",
];

const pipelineData = (overrides: Record<string, unknown> = {}) => ({
    bill: { id: 42, external_id: "25-0001", title: "A bill" },
    selected_stages: DEFAULT_STAGES,
    download_missing_assets: true,
    pipeline_preview: null,
    ...overrides,
});

const renderSection = (billId: number | null = 42, data = pipelineData(), refresh = jest.fn(async () => {})) => {
    render(<PipelineStagesSection billId={billId} data={data} refresh={refresh} />);
    return refresh;
};

const toggle = (stage: string) => fireEvent.press(screen.getByTestId(`admin-pipeline-stage-${stage}`));

const settlePreview = () => act(async () => {});

const isChecked = (testID: string) => screen.getByTestId(testID).props.accessibilityState?.checked;

// @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
describe("PipelineStagesSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue({ pipeline_preview: null });
        mockApiPost.mockResolvedValue({});
    });

    it("starts a run with the selected stages and refreshes the tab", async () => {
        const refresh = renderSection();

        toggle("fetch-law");
        toggle("summarize-bill");
        fireEvent.press(screen.getByTestId("admin-pipeline-run"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost).toHaveBeenCalledWith("/bills/run_pipeline", {
            stages: [
                "fetch-bills",
                "extract-text",
                "parse-sections",
                "generate-diffs",
                "fetch-hearings",
                "clean-testimony",
                "summarize-bill",
            ],
            bill_id: 42,
            sway_locale_id: 7,
            download_missing_assets: true,
        });
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
        expect(screen.getByText("Pipeline run queued.")).toBeTruthy();
    });

    it("names the bill or all bills and the locale on the run button", () => {
        renderSection();
        expect(screen.getByText("Run pipeline for bill 25-0001 in Baltimore")).toBeTruthy();
    });

    it("runs every bill of the locale for a new bill", async () => {
        renderSection(null, pipelineData({ bill: undefined }));
        expect(screen.getByText("Run pipeline for all bills in Baltimore")).toBeTruthy();

        fireEvent.press(screen.getByTestId("admin-pipeline-run"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(1));
        expect(mockApiPost.mock.calls[0][1]).toMatchObject({ bill_id: null, sway_locale_id: 7 });
    });

    it("counts the selection and disables Select all and Clear all at their ends", async () => {
        renderSection();
        expect(screen.getByText("7 of 8 selected")).toBeTruthy();

        fireEvent.press(screen.getByTestId("admin-pipeline-select-all"));
        expect(screen.getByText("8 of 8 selected")).toBeTruthy();
        expect(screen.getByTestId("admin-pipeline-select-all").props.accessibilityState?.disabled).toBe(true);

        fireEvent.press(screen.getByTestId("admin-pipeline-clear-all"));
        expect(screen.getByText("0 of 8 selected")).toBeTruthy();
        expect(screen.getByTestId("admin-pipeline-clear-all").props.accessibilityState?.disabled).toBe(true);
        await settlePreview();
    });

    it("disables the run and says why when no stage is selected", () => {
        renderSection();

        fireEvent.press(screen.getByTestId("admin-pipeline-clear-all"));

        expect(screen.getByTestId("admin-pipeline-run").props.accessibilityState?.disabled).toBe(true);
        expect(screen.getByText("Pick at least one stage to run.")).toBeTruthy();
        fireEvent.press(screen.getByTestId("admin-pipeline-run"));
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("locks Download missing assets on while both fetch stages are selected", async () => {
        renderSection(42, pipelineData({ download_missing_assets: false }));

        expect(isChecked("admin-pipeline-download-missing-assets")).toBe(true);
        expect(screen.getByTestId("admin-pipeline-download-missing-assets").props.accessibilityState?.disabled).toBe(
            true,
        );
        expect(screen.getByText("Both fetch stages are checked — there is nothing to backfill.")).toBeTruthy();

        toggle("fetch-hearings");

        expect(isChecked("admin-pipeline-download-missing-assets")).toBe(false);
        fireEvent.press(screen.getByTestId("admin-pipeline-download-missing-assets"));
        expect(isChecked("admin-pipeline-download-missing-assets")).toBe(true);
        await settlePreview();
    });

    it("asks the server for a preview of the new selection and shows its warnings", async () => {
        mockApiGet.mockResolvedValue({
            pipeline_preview: {
                stages_requested: ["generate-diffs"],
                stages_will_run: ["extract-text", "generate-diffs"],
                stages_auto_included: ["extract-text"],
                confirmation_required: true,
                confirmation_message: null,
                prereq_violations: [
                    { stage: "generate-diffs", missing_artifact: "law text", bill_count: 3, prerequisite: "fetch-law" },
                ],
            },
        });
        renderSection(42, pipelineData({ selected_stages: ["generate-diffs", "fetch-law"] }));

        fireEvent.press(screen.getByTestId("admin-pipeline-download-missing-assets"));
        toggle("fetch-law");

        await waitFor(() =>
            expect(mockApiGet).toHaveBeenLastCalledWith(
                "/admin/bill_creator/42/pipeline?selected_stages=generate-diffs&download_missing_assets=0",
                expect.objectContaining({ signal: expect.anything() }),
            ),
        );
        expect(await screen.findByText("Also required")).toBeTruthy();
        expect(screen.getByTestId("admin-pipeline-auto-included").props.children).toBe("Extract text");
        expect(screen.getByTestId("admin-pipeline-auto-include-reduced-note")).toBeTruthy();
        expect(
            screen.getByText(
                "3 bills will FAIL Generate diffs because they have no law text — enable Download missing assets or check Fetch law",
            ),
        ).toBeTruthy();
    });

    it("shows the reason the server refused the run", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { pipeline: "A SwayLocale is required for all-bills pipeline runs." },
                422,
            ),
        );
        const refresh = renderSection();

        fireEvent.press(screen.getByTestId("admin-pipeline-run"));

        expect(await screen.findByText("A SwayLocale is required for all-bills pipeline runs.")).toBeTruthy();
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows the server message when a run is already active", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError("duplicate_run", "Pipeline already running (run #9)", { existing_run_id: 9 }, 409),
        );
        renderSection();

        fireEvent.press(screen.getByTestId("admin-pipeline-run"));

        expect(await screen.findByText("Pipeline already running (run #9)")).toBeTruthy();
    });
});
