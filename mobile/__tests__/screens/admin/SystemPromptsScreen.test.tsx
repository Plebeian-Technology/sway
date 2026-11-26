import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../src/api/errors";

const mockApiGet = jest.fn();
jest.mock("../../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockApiGet(...args) },
}));

jest.mock("../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import SystemPromptsScreen from "../../../src/screens/admin/SystemPromptsScreen";

const availablePrompt = {
    id: "bill_positions",
    label: "Organization positions",
    purpose: "Sent once per bill to draw organization positions out of the hearing testimony.",
    builder: "BillPositionsPromptBuilder",
    model: "claude-opus-5-5",
    model_setting_label: "Summarization model",
    system_prompt: "You extract organization positions from testimony.",
    character_count: 50,
    unavailable_reason: null,
    sway_locale_name: null,
};

const unavailablePrompt = {
    id: "bill_categories",
    label: "Bill categories",
    purpose: "Sent by the category backfill for a summarised bill that still carries no active category.",
    builder: "BillCategoryPromptBuilder",
    model: "claude-opus-5-5",
    model_setting_label: "Summarization model",
    system_prompt: null,
    character_count: null,
    unavailable_reason: "No categorisation prompt is sent on this installation.",
    sway_locale_name: null,
};

const localePrompt = {
    ...availablePrompt,
    id: "bill_summary_baltimore",
    label: "Bill summary",
    system_prompt: "You summarise Baltimore bills.",
    character_count: 30,
    sway_locale_name: "baltimore-maryland-united_states",
};

const catalog = {
    models: { summarization: "claude-opus-5-5", classification: "claude-haiku-5-5" },
    active_category_count: 3,
    llm_settings_path: "/admin/llm_settings",
    prompts: [localePrompt, availablePrompt, unavailablePrompt],
};

// @lat: [[mobile-admin-area#The system prompts screen]]
describe("SystemPromptsScreen", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("shows the models and the category count", async () => {
        mockApiGet.mockResolvedValue(catalog);
        render(<SystemPromptsScreen />);

        expect(await screen.findByText("claude-haiku-5-5")).toBeTruthy();
        expect(screen.getByText("Summarization model")).toBeTruthy();
        expect(screen.getByText("Testimony classification model")).toBeTruthy();
        expect(screen.getByText(/3 active categories/)).toBeTruthy();
        expect(mockApiGet).toHaveBeenCalledWith("/admin/system_prompts", expect.anything());
    });

    it("expands a prompt row to show its text and collapses it again", async () => {
        mockApiGet.mockResolvedValue(catalog);
        render(<SystemPromptsScreen />);

        const row = await screen.findByText("Organization positions");
        expect(screen.queryByText("You extract organization positions from testimony.")).toBeNull();

        fireEvent.press(row);
        expect(screen.getByText("You extract organization positions from testimony.")).toBeTruthy();
        expect(screen.getByText("50 characters")).toBeTruthy();
        expect(screen.getByText("Builder: BillPositionsPromptBuilder")).toBeTruthy();

        fireEvent.press(row);
        expect(screen.queryByText("You extract organization positions from testimony.")).toBeNull();
    });

    it("shows the locale name on a per-locale prompt", async () => {
        mockApiGet.mockResolvedValue(catalog);
        render(<SystemPromptsScreen />);

        expect(await screen.findByText("baltimore-maryland-united_states")).toBeTruthy();
    });

    it("shows why an unavailable prompt is not sent", async () => {
        mockApiGet.mockResolvedValue(catalog);
        render(<SystemPromptsScreen />);

        const row = await screen.findByText("Bill categories");
        expect(screen.getByText("Not sent")).toBeTruthy();
        expect(screen.queryByText("No categorisation prompt is sent on this installation.")).toBeNull();

        fireEvent.press(row);
        expect(screen.getByText("No categorisation prompt is sent on this installation.")).toBeTruthy();
    });

    it("warns when no category is active", async () => {
        mockApiGet.mockResolvedValue({ ...catalog, active_category_count: 0 });
        render(<SystemPromptsScreen />);

        expect(await screen.findByText("No active categories")).toBeTruthy();
    });

    it("shows the server's message when the request fails", async () => {
        mockApiGet.mockRejectedValue(
            new ApiRequestError("forbidden", "You are not allowed to do that.", undefined, 403),
        );
        render(<SystemPromptsScreen />);

        await waitFor(() => expect(screen.getByText("You are not allowed to do that.")).toBeTruthy());
    });
});
