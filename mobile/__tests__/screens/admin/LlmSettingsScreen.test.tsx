import React from "react";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
const mockApiPatch = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
    },
}));

jest.mock("../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import LlmSettingsScreen from "../../../src/screens/admin/LlmSettingsScreen";

const HAIKU = { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false };
const SONNET = { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true, supports_reasoning: true };
const OPUS = { id: "claude-opus-5-5", label: "Opus 5.5", selectable: true, supports_reasoning: true };
const RETIRED = { id: "claude-retired", label: "Retired model", selectable: false, supports_reasoning: false };
const SCALEDOWN = { id: "ScaleDown Classify Latest", label: "ScaleDown Classify Latest", selectable: true };
const SCALEDOWN_EXTRACT = { id: "ScaleDown Extract Latest", label: "ScaleDown Extract Latest", selectable: true };

const settings = (overrides: Record<string, unknown> = {}) => ({
    supported_models: [HAIKU, SONNET, OPUS, RETIRED],
    supported_decision_models: [SCALEDOWN],
    supported_extraction_models: [SCALEDOWN_EXTRACT],
    available_openrouter_models: [],
    current_summarization_model: HAIKU.id,
    current_classification_model: HAIKU.id,
    current_decision_model: SCALEDOWN.id,
    current_extraction_model: SCALEDOWN_EXTRACT.id,
    current_summarization_reasoning_effort: null,
    current_classification_reasoning_effort: null,
    current_summary_batch_enabled: false,
    updated_by: { name: "Ada Admin" },
    updated_at: "2026-11-01T12:00:00Z",
    ...overrides,
});

const STALE_COPY = "Someone else changed these settings. Pull to refresh, then save again.";

const chooseSummarizationModel = (modelId: string) => {
    fireEvent.press(screen.getByTestId("admin-llm-summarization_model-toggle"));
    fireEvent.press(screen.getByTestId(`admin-llm-summarization_model-option-${modelId}`));
};

// @lat: [[mobile-admin-area#The LLM settings screen]]
describe("LlmSettingsScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiGet.mockResolvedValue(settings());
    });

    it("shows the current model of each task and who last changed them", async () => {
        render(<LlmSettingsScreen />);

        expect(await screen.findByTestId("admin-llm-summarization_model-current")).toHaveTextContent("Haiku 5.5");
        expect(screen.getByTestId("admin-llm-classification_model-current")).toHaveTextContent("Haiku 5.5");
        expect(screen.getByTestId("admin-llm-decision_model-current")).toHaveTextContent("ScaleDown Classify Latest");
        expect(screen.getByTestId("admin-llm-extraction_model-current")).toHaveTextContent("ScaleDown Extract Latest");
        expect(screen.getByText(/Last changed by Ada Admin/)).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/llm_settings", expect.anything());
    });

    it("shows the raw id when the current model is not in the offered list", async () => {
        mockApiGet.mockResolvedValue(settings({ current_summarization_model: "claude-unlisted" }));
        render(<LlmSettingsScreen />);

        expect(await screen.findByTestId("admin-llm-summarization_model-current")).toHaveTextContent("claude-unlisted");
    });

    it("keeps Save off until a setting changes", async () => {
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        expect(screen.getByTestId("admin-llm-save").props.accessibilityState.disabled).toBe(true);
        chooseSummarizationModel(SONNET.id);
        expect(screen.getByTestId("admin-llm-save").props.accessibilityState.disabled).toBe(false);
    });

    it("does not let an admin pick a model the server marks as not selectable", async () => {
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        fireEvent.press(screen.getByTestId("admin-llm-summarization_model-toggle"));
        expect(
            screen.getByTestId(`admin-llm-summarization_model-option-${RETIRED.id}`).props.accessibilityState.disabled,
        ).toBe(true);
    });

    it("saves a changed summarization model with the value it loaded as the expected block", async () => {
        mockApiPatch.mockResolvedValue({});
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        chooseSummarizationModel(SONNET.id);
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/llm_settings", {
                admin_setting: {
                    summarization_model: SONNET.id,
                    expected: { summarization_model: HAIKU.id },
                },
            }),
        );
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
    });

    it("sends a reasoning level only for a model that supports one, with the empty default as expected", async () => {
        mockApiPatch.mockResolvedValue({});
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        expect(screen.queryByTestId("admin-llm-summarization_model-effort")).toBeNull();
        chooseSummarizationModel(SONNET.id);
        fireEvent.press(screen.getByTestId("admin-llm-summarization_model-effort-segment-3"));
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/llm_settings", {
                admin_setting: {
                    summarization_model: SONNET.id,
                    summarization_reasoning_effort: "high",
                    expected: { summarization_model: HAIKU.id, summarization_reasoning_effort: "" },
                },
            }),
        );
    });

    it("clears the reasoning level when the model changes to one without reasoning", async () => {
        mockApiGet.mockResolvedValue(
            settings({
                current_summarization_model: SONNET.id,
                current_summarization_reasoning_effort: "low",
            }),
        );
        mockApiPatch.mockResolvedValue({});
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        chooseSummarizationModel(HAIKU.id);
        expect(screen.queryByTestId("admin-llm-summarization_model-effort")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/llm_settings", {
                admin_setting: {
                    summarization_model: HAIKU.id,
                    summarization_reasoning_effort: "",
                    expected: { summarization_model: SONNET.id, summarization_reasoning_effort: "low" },
                },
            }),
        );
    });

    it("sends the batch switch as a boolean", async () => {
        mockApiPatch.mockResolvedValue({});
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        fireEvent(screen.getByTestId("pref-switch-summary_batch_enabled"), "valueChange", true);
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/admin/llm_settings", {
                admin_setting: { summary_batch_enabled: true, expected: { summary_batch_enabled: false } },
            }),
        );
    });

    it("shows the mobile copy, not the server's message, when someone else saved first", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError(
                "stale_write",
                "summarization_model is now claude-opus-5-5, not the value you sent as expected. GET /admin/llm_settings for the current settings, then submit again.",
                undefined,
                409,
            ),
        );
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        chooseSummarizationModel(SONNET.id);
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        expect(await screen.findByText(STALE_COPY)).toBeTruthy();
        expect(screen.queryByText(/GET \/admin\/llm_settings/)).toBeNull();
        expect(mockApiGet).toHaveBeenCalledTimes(1);
    });

    it("builds the next expected block from the settings it reloaded after a stale save", async () => {
        mockApiPatch.mockRejectedValueOnce(new ApiRequestError("stale_write", "Moved.", undefined, 409));
        mockApiPatch.mockResolvedValueOnce({});
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        chooseSummarizationModel(SONNET.id);
        fireEvent.press(screen.getByTestId("admin-llm-save"));
        await screen.findByText(STALE_COPY);

        mockApiGet.mockResolvedValue(settings({ current_summarization_model: OPUS.id }));
        await act(async () => {
            screen.getByTestId("admin-llm-settings-screen").props.refreshControl.props.onRefresh();
        });
        await waitFor(() =>
            expect(screen.getByTestId("admin-llm-summarization_model-current")).toHaveTextContent("Opus 5.5"),
        );
        expect(screen.queryByText(STALE_COPY)).toBeNull();

        chooseSummarizationModel(SONNET.id);
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenLastCalledWith("/admin/llm_settings", {
                admin_setting: {
                    summarization_model: SONNET.id,
                    expected: { summarization_model: OPUS.id },
                },
            }),
        );
    });

    it("shows the server's message when the save is rejected", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError("validation_failed", "Model not recognized.", undefined, 422),
        );
        render(<LlmSettingsScreen />);
        await screen.findByTestId("admin-llm-summarization_model-current");

        chooseSummarizationModel(SONNET.id);
        fireEvent.press(screen.getByTestId("admin-llm-save"));

        expect(await screen.findByText("Model not recognized.")).toBeTruthy();
        expect(screen.queryByText(STALE_COPY)).toBeNull();
    });

    it("shows the server's message when the settings request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<LlmSettingsScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});
