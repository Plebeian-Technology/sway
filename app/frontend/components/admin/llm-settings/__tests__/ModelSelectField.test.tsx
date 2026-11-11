import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

// @lat: [[bill-creator-shell#The Bill Creator shell#Why a Radix portal is stubbed rather than driven in tests]]
vi.mock("app/frontend/components/ui/combobox", () => ({
    Combobox: ({
        id,
        "aria-label": ariaLabel,
        value,
        options,
        "aria-invalid": ariaInvalid,
        "aria-describedby": ariaDescribedby,
        searchPlaceholder,
        emptyText,
    }: {
        id?: string;
        "aria-label"?: string;
        value: string;
        options: Array<{ value: string; label: string; keywords?: string; disabled?: boolean }>;
        "aria-invalid"?: boolean;
        "aria-describedby"?: string;
        searchPlaceholder?: string;
        emptyText?: string;
    }) => (
        <div
            id={id}
            // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role
            role="combobox"
            aria-expanded="false"
            aria-controls="mock-controls"
            aria-label={ariaLabel}
            aria-invalid={ariaInvalid ? "true" : undefined}
            aria-describedby={ariaDescribedby}
            data-search-placeholder={searchPlaceholder}
            data-empty-text={emptyText}
        >
            <div data-testid="combobox-value">{value}</div>
            {options.map((option) => (
                <div
                    key={option.value}
                    data-testid={`option-${option.value}`}
                    data-disabled={option.disabled ? "true" : "false"}
                    data-keywords={option.keywords}
                >
                    {option.label}
                </div>
            ))}
        </div>
    ),
}));

import ModelSelectField from "app/frontend/components/admin/llm-settings/ModelSelectField";

afterEach(cleanup);

const renderField = (options: React.ComponentProps<typeof ModelSelectField>["options"], error?: string) =>
    render(
        <ModelSelectField
            id="summarization-model"
            label="Summarization model"
            description="Runs once per bill."
            value="claude-opus-5-5"
            options={options}
            error={error}
            onChange={vi.fn<(value: string) => void>()}
        />,
    );

describe("ModelSelectField", () => {
    it("lets an offered model be picked", () => {
        renderField([{ id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true }]);

        const option = screen.getByTestId("option-claude-sonnet-5-5");
        expect(option).toHaveAttribute("data-disabled", "false");
        expect(option).toHaveAttribute("data-keywords", "claude-sonnet-5-5");
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    it("shows a model that is no longer offered, and does not let it be picked", () => {
        renderField([
            { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
            { id: "claude-opus-5-5", label: "claude-opus-5-5 — no longer offered", selectable: false },
        ]);

        const retired = screen.getByTestId("option-claude-opus-5-5");
        expect(retired).toHaveTextContent("no longer offered");
        expect(retired).toHaveAttribute("data-disabled", "true");
        expect(retired).toHaveAttribute("data-keywords", "claude-opus-5-5");
    });

    it("forwards aria attributes and search placeholders to Combobox", () => {
        renderField([{ id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true }], "Invalid model");

        const combobox = screen.getByRole("combobox");
        expect(combobox).toHaveAttribute("id", "summarization-model");
        expect(combobox).toHaveAttribute("aria-label", "Summarization model");
        expect(combobox).toHaveAttribute("aria-invalid", "true");
        expect(combobox).toHaveAttribute(
            "aria-describedby",
            "summarization-model-error summarization-model-description",
        );
        expect(combobox).toHaveAttribute("data-search-placeholder", "Search models...");
        expect(combobox).toHaveAttribute("data-empty-text", "No matching models.");
    });

    it("renders reasoning level selector when selected model supports reasoning", () => {
        const onReasoningEffortChange = vi.fn<(effort: string) => void>();
        render(
            <ModelSelectField
                id="summarization-model"
                label="Summarization model"
                description="Runs once per bill."
                value="Gemini Argon Latest"
                options={[
                    {
                        id: "Gemini Argon Latest",
                        label: "Gemini Argon Latest",
                        selectable: true,
                        supports_reasoning: true,
                    },
                    { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
                ]}
                reasoningEffort="medium"
                onReasoningEffortChange={onReasoningEffortChange}
                onChange={vi.fn<(value: string) => void>()}
            />,
        );

        const select = screen.getByRole("combobox", {
            name: "Summarization model reasoning level",
        }) as HTMLSelectElement;
        expect(select).toBeInTheDocument();
        expect(select.value).toBe("medium");

        const options = Array.from(select.querySelectorAll("option")).map((o) => ({
            value: o.value,
            text: o.textContent,
        }));
        expect(options).toEqual([
            { value: "", text: "Default" },
            { value: "low", text: "Low" },
            { value: "medium", text: "Medium" },
            { value: "high", text: "High" },
        ]);

        select.value = "high";
        select.dispatchEvent(new Event("change", { bubbles: true }));
        expect(onReasoningEffortChange).toHaveBeenCalledWith("high");
    });

    it("forwards aria-invalid and aria-describedby to the reasoning level selector when error is present", () => {
        render(
            <ModelSelectField
                id="summarization-model"
                label="Summarization model"
                description="Runs once per bill."
                value="Gemini Argon Latest"
                options={[
                    {
                        id: "Gemini Argon Latest",
                        label: "Gemini Argon Latest",
                        selectable: true,
                        supports_reasoning: true,
                    },
                ]}
                reasoningEffort="high"
                error="Invalid reasoning effort"
                onChange={vi.fn<(value: string) => void>()}
            />,
        );

        const select = screen.getByRole("combobox", {
            name: "Summarization model reasoning level",
        });
        expect(select).toHaveAttribute("aria-invalid", "true");
        expect(select).toHaveAttribute("aria-describedby", "summarization-model-error summarization-model-description");
    });

    it("does not render reasoning level selector when selected model does not support reasoning", () => {
        render(
            <ModelSelectField
                id="summarization-model"
                label="Summarization model"
                description="Runs once per bill."
                value="claude-haiku-5-5"
                options={[
                    {
                        id: "Gemini Argon Latest",
                        label: "Gemini Argon Latest",
                        selectable: true,
                        supports_reasoning: true,
                    },
                    { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
                ]}
                onChange={vi.fn<(value: string) => void>()}
            />,
        );

        expect(screen.queryByLabelText("Summarization model reasoning level")).toBeNull();
    });
});
