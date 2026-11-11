// @lat: [[classification-model-switching-cost#Why CLASSIFIER_MODEL is independent of the summarization default]]

import * as React from "react";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

// @lat: [[inertia-nested-form-errors-accessor#Reading errors from a nested Inertia form]]
// `mockErrors` lets a test feed BOTH shapes.
let mockErrors: Record<string, unknown> = {};

const { routerPostMock, routerDeleteMock, setDataMock, usePollMock, formPatchMock, formTransformMock } = vi.hoisted(
    () => ({
        routerPostMock: vi.fn<(url: string, data?: unknown, options?: unknown) => void>(),
        routerDeleteMock: vi.fn<(url: string, options?: unknown) => void>(),
        setDataMock: vi.fn<(key: string, value: unknown) => void>(),
        usePollMock: vi.fn<(interval: number, options: { only: string[] }) => void>(),
        formPatchMock: vi.fn<(url: string, options?: unknown) => void>(),
        formTransformMock: vi.fn<(fn: () => unknown) => void>(),
    }),
);

vi.mock("@inertiajs/react", () => ({
    router: {
        on: vi.fn<() => void>(),
        get: vi.fn<() => void>(),
        post: routerPostMock,
        delete: routerDeleteMock,
        reload: vi.fn<() => void>(),
    },
    usePoll: function usePoll(interval: number, options: { only: string[] }) {
        usePollMock(interval, options);
    },
    usePage: () => ({ props: { flash: {}, errors: mockErrors } }),
    useForm: (initial: unknown) => {
        const [formData, setFormData] = React.useState(initial as { admin_setting: Record<string, unknown> });
        const setData = (key: string, value: unknown) => {
            setDataMock(key, value);
            if (key === "admin_setting") {
                setFormData({ admin_setting: value as Record<string, unknown> });
            } else if (key.startsWith("admin_setting.")) {
                const field = key.replace("admin_setting.", "");
                setFormData((prev) => ({
                    ...prev,
                    admin_setting: {
                        ...prev.admin_setting,
                        [field]: value,
                    },
                }));
            } else {
                setFormData((prev) => ({ ...prev, [key]: value }));
            }
        };
        return {
            data: formData,
            setData,
            patch: formPatchMock,
            transform: formTransformMock,
            processing: false,
            errors: mockErrors,
        };
    },
    Link: ({ children, href, ...rest }: { children: React.ReactNode; href: string; [key: string]: unknown }) => (
        <a href={href} {...(rest as Record<string, unknown>)}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/components/ui/combobox", () => ({
    Combobox: ({
        id,
        "aria-label": ariaLabel,
        value,
        options,
        onValueChange,
        placeholder,
        searchPlaceholder,
        emptyText,
        "aria-invalid": ariaInvalid,
        "aria-describedby": ariaDescribedby,
    }: {
        id?: string;
        "aria-label"?: string;
        value: string;
        options: Array<{ value: string; label: string; keywords?: string; disabled?: boolean }>;
        onValueChange: (val: string) => void;
        placeholder?: string;
        searchPlaceholder?: string;
        emptyText?: string;
        "aria-invalid"?: boolean;
        "aria-describedby"?: string;
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
            <span data-testid={`${id}-value`}>{value || placeholder}</span>
            <select data-testid={`${id}-select`} value={value} onChange={(e) => onValueChange(e.target.value)}>
                <option value="">Select</option>
                {options.map((opt) => (
                    <option key={opt.value} value={opt.value} disabled={opt.disabled} data-keywords={opt.keywords}>
                        {opt.label}
                    </option>
                ))}
            </select>
        </div>
    ),
}));

vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    SelectTrigger: ({ children, ...rest }: { children: React.ReactNode }) => <button {...rest}>{children}</button>,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    SelectItem: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import LlmSettings from "app/frontend/pages/admin/LlmSettings";

afterEach(() => {
    cleanup();
    mockErrors = {};
    setDataMock.mockClear();
    routerPostMock.mockClear();
    routerDeleteMock.mockClear();
    usePollMock.mockClear();
    formPatchMock.mockClear();
    formTransformMock.mockClear();
});

const renderPage = (batchEnabled = false) =>
    render(
        <LlmSettings
            supported_models={[
                { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
                { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
            ]}
            current_summarization_model="claude-haiku-5-5"
            current_classification_model="claude-haiku-5-5"
            current_summary_batch_enabled={batchEnabled}
            updated_by={null}
            updated_at="2026-07-27T00:00:00Z"
        />,
    );

describe("Admin LLM Settings — background polling", () => {
    it("polls every 15 seconds including supported_models and current settings props", () => {
        renderPage();

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock.mock.calls[0][0]).toBe(15000);
        expect(usePollMock.mock.calls[0][1].only).toEqual([
            "supported_models",
            "supported_decision_models",
            "supported_extraction_models",
            "available_openrouter_models",
            "current_summarization_model",
            "current_classification_model",
            "current_decision_model",
            "current_extraction_model",
            "current_summarization_reasoning_effort",
            "current_classification_reasoning_effort",
            "current_summary_batch_enabled",
            "updated_by",
            "updated_at",
        ]);
    });
});

describe("Admin LLM Settings — classification switching cost (B2-IN-05)", () => {
    it("tells the operator that changing the classification model re-classifies everything already decided", () => {
        renderPage();

        const description = screen.getByText(/Decides whether each hearing attachment/i).textContent ?? "";

        expect(description).toMatch(/re-classif/i);
        expect(description).toMatch(/already/i);
    });

    it("does not claim the same switching cost for the summarization model, which has no verdict cache", () => {
        renderPage();

        const description = screen.getByText(/Runs once per bill/i).textContent ?? "";

        expect(description).not.toMatch(/re-classif/i);
    });
});

describe("Admin LLM Settings — link to the prompts sent with these models", () => {
    it("points at /admin/system_prompts", () => {
        renderPage();

        expect(screen.getByTestId("link-system-prompts")).toHaveAttribute("href", "/admin/system_prompts");
    });
});

// @lat: [[inertia-nested-form-errors-accessor#Reading errors from a nested Inertia form]]
describe("Admin LLM Settings — validation errors survive either errors shape (C1-IN-07)", () => {
    it("renders a nested admin_setting error", () => {
        mockErrors = { admin_setting: { summarization_model: "is not an allowed model" } };
        renderPage();

        expect(screen.getByText("is not an allowed model")).toBeInTheDocument();
        expect(screen.getByLabelText("Summarization model")).toHaveAttribute("aria-invalid", "true");
    });

    it("renders a dotted-path admin_setting error", () => {
        mockErrors = { "admin_setting.classification_model": "is not an allowed model" };
        renderPage();

        expect(screen.getByText("is not an allowed model")).toBeInTheDocument();
        expect(screen.getByLabelText("Testimony classification model")).toHaveAttribute("aria-invalid", "true");
    });

    it("renders no error text when the save was accepted", () => {
        renderPage();

        expect(screen.queryByText("is not an allowed model")).toBeNull();
        expect(screen.getByLabelText("Summarization model")).not.toHaveAttribute("aria-invalid");
    });

    it("renders summarization reasoning effort error via ModelSelectField", () => {
        mockErrors = {
            admin_setting: {
                summarization_reasoning_effort: "is not an allowed reasoning effort",
            },
        };
        renderPage();

        expect(screen.getByText("is not an allowed reasoning effort")).toBeInTheDocument();
        expect(screen.getByLabelText("Summarization model")).toHaveAttribute("aria-invalid", "true");
    });

    it("renders classification reasoning effort error via ModelSelectField", () => {
        mockErrors = {
            admin_setting: {
                classification_reasoning_effort: "is not an allowed reasoning effort",
            },
        };
        renderPage();

        expect(screen.getByText("is not an allowed reasoning effort")).toBeInTheDocument();
        expect(screen.getByLabelText("Testimony classification model")).toHaveAttribute("aria-invalid", "true");
    });
});

const BATCH_SWITCH = { name: "Batch bill summarization" };

// @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
describe("Admin LLM Settings — batch summarisation switch", () => {
    it("renders the switch off when the stored setting is off", () => {
        renderPage();

        expect(screen.getByRole("switch", BATCH_SWITCH)).not.toBeChecked();
    });

    it("renders the switch on when the stored setting is on", () => {
        renderPage(true);

        expect(screen.getByRole("switch", BATCH_SWITCH)).toBeChecked();
    });

    it("submits the new value through the form's nested admin_setting key", () => {
        renderPage();

        fireEvent.click(screen.getByRole("switch", BATCH_SWITCH));

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summary_batch_enabled", true);
    });

    it("turns the switch back off from an enabled page", () => {
        renderPage(true);

        fireEvent.click(screen.getByRole("switch", BATCH_SWITCH));

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summary_batch_enabled", false);
    });

    it("says what turning it on does, what it costs in latency, and why it is off by default", () => {
        renderPage();

        const description = screen.getByText(/full pipeline run sends its bill summarization/i).textContent ?? "";

        expect(description).toMatch(/in batches instead of one call per bill/i);
        expect(description).toMatch(/cost less/i);
        expect(description).toMatch(/24 hours/i);
        expect(description).toMatch(/arrive together rather than bill by bill/i);
        expect(description).toMatch(/off by default/i);
        expect(description).toMatch(/not yet been proven against a production run/i);
    });

    it("wires the help text to the switch for a screen reader", () => {
        renderPage();

        expect(screen.getByRole("switch", BATCH_SWITCH)).toHaveAttribute(
            "aria-describedby",
            expect.stringContaining("summary-batch-enabled-description"),
        );
    });

    it("shows a server error for the switch and marks it invalid", () => {
        mockErrors = { admin_setting: { summary_batch_enabled: "could not be saved" } };
        renderPage();

        expect(screen.getByText("could not be saved")).toBeInTheDocument();
        expect(screen.getByRole("switch", BATCH_SWITCH)).toHaveAttribute("aria-invalid", "true");
    });
});

describe("Admin LLM Settings — candidate OpenRouter choices flat display", () => {
    it("renders candidate OpenRouter choices as flat items without optgroups or provider badges", () => {
        const candidateModels: Array<{ id: string; label: string; selectable: boolean }> = [
            { id: "claude-haiku-5-5", label: "Haiku 5.5 — fast & cheap (default)", selectable: true },
            { id: "claude-sonnet-5-5", label: "Sonnet 5.5 — balanced", selectable: true },
            { id: "claude-opus-5-5", label: "Opus 5.5 — maximum quality", selectable: true },
            { id: "Deepseek Pro Latest", label: "Deepseek Pro Latest", selectable: true },
            { id: "Deepseek Flash Latest", label: "Deepseek Flash Latest", selectable: true },
            { id: "OpenRouter Auto", label: "OpenRouter Auto", selectable: true },
        ];

        render(
            <LlmSettings
                supported_models={candidateModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        // Confirm the exact model labels are rendered
        expect(screen.getAllByText("Deepseek Pro Latest").length).toBeGreaterThan(0);
        expect(screen.getAllByText("Deepseek Flash Latest").length).toBeGreaterThan(0);
        expect(screen.getAllByText("OpenRouter Auto").length).toBeGreaterThan(0);

        // Confirm no optgroup, selectgroup, or provider badge exists
        expect(screen.queryByRole("group")).not.toBeInTheDocument();
        expect(screen.queryByText(/Provider/i)).not.toBeInTheDocument();
        expect(screen.queryByText(/Anthropic/i)).not.toBeInTheDocument();
        expect(screen.queryByText(/OpenRouter —/i)).not.toBeInTheDocument();
    });
});

describe("Admin LLM Settings — Offered Models management card", () => {
    const supportedModels = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
        { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
        { id: "openai/gpt-4o", label: "OpenAI: GPT-4o", selectable: true },
    ];
    const availableOpenRouterModels = [
        { id: "deepseek/deepseek-chat", label: "DeepSeek: Chat" },
        { id: "meta-llama/llama-3.3-70b-instruct", label: "Meta: Llama 3.3 70B Instruct" },
    ];

    it("renders offered models and disables removal of active summarization and classification models", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByText("Offered Models")).toBeInTheDocument();
        expect(screen.getByTestId("btn-remove-model-claude-haiku-5-5")).toBeDisabled();
        expect(screen.getByTestId("btn-remove-model-claude-sonnet-5-5")).toBeDisabled();
        expect(screen.getByTestId("btn-remove-model-openai/gpt-4o")).toBeEnabled();
    });

    it("disables the Remove button when only one offered model remains, even if not active", () => {
        render(
            <LlmSettings
                supported_models={[
                    { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
                    { id: "retired-model", label: "Retired Model", selectable: false },
                ]}
                current_summarization_model="retired-model"
                current_classification_model="retired-model"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByTestId("btn-remove-model-claude-haiku-5-5")).toBeDisabled();
    });

    it("renders an error alert when offered_models validation error is present at top level", () => {
        mockErrors = {
            offered_models: "Offered models cannot remove a model that is currently active",
        };
        renderPage();

        const alert = screen.getByRole("alert");
        expect(alert).toHaveTextContent("Offered models cannot remove a model that is currently active");
    });

    it("renders an error alert when offered_models validation error is nested under admin_setting", () => {
        mockErrors = {
            admin_setting: {
                offered_models: "Offered models cannot remove a model that is currently active",
            },
        };
        renderPage();

        const alert = screen.getByRole("alert");
        expect(alert).toHaveTextContent("Offered models cannot remove a model that is currently active");
    });

    it("dispatches router.delete when removing an unassigned offered model", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.click(screen.getByTestId("btn-remove-model-openai/gpt-4o"));

        expect(routerDeleteMock).toHaveBeenCalledWith(
            "/admin/llm_settings/remove_model",
            expect.objectContaining({
                data: { model_id: "openai/gpt-4o" },
                preserveScroll: true,
            }),
        );
    });

    it("disables removal of an offered model when it is selected in unsaved summarization form state", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const removeButton = screen.getByTestId("btn-remove-model-openai/gpt-4o");
        expect(removeButton).toBeEnabled();

        fireEvent.change(screen.getByTestId("summarization-model-select"), {
            target: { value: "openai/gpt-4o" },
        });

        expect(removeButton).toBeDisabled();

        fireEvent.change(screen.getByTestId("summarization-model-select"), {
            target: { value: "claude-haiku-5-5" },
        });
        expect(removeButton).toBeEnabled();
    });

    it("disables removal of an offered model when it is selected in unsaved classification form state", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const removeButton = screen.getByTestId("btn-remove-model-openai/gpt-4o");
        expect(removeButton).toBeEnabled();

        fireEvent.change(screen.getByTestId("classification-model-select"), {
            target: { value: "openai/gpt-4o" },
        });

        expect(removeButton).toBeDisabled();

        fireEvent.change(screen.getByTestId("classification-model-select"), {
            target: { value: "claude-haiku-5-5" },
        });

        expect(removeButton).toBeEnabled();
    });

    it("renders Active badges for active summarization and classification models and omits them for inactive models", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const activeBadges = screen.getAllByText("Active");
        expect(activeBadges).toHaveLength(2);

        const haikuItem = screen.getByTestId("btn-remove-model-claude-haiku-5-5").closest("li");
        const sonnetItem = screen.getByTestId("btn-remove-model-claude-sonnet-5-5").closest("li");
        const gpt4oItem = screen.getByTestId("btn-remove-model-openai/gpt-4o").closest("li");

        expect(haikuItem).toHaveTextContent("Active");
        expect(sonnetItem).toHaveTextContent("Active");
        expect(gpt4oItem).not.toHaveTextContent("Active");
    });

    it("enables removal when multiple offered models exist and none are active or selected, and disables when offeredModels.length <= 1", () => {
        const { unmount } = render(
            <LlmSettings
                supported_models={[
                    { id: "model-a", label: "Model A", selectable: true },
                    { id: "model-b", label: "Model B", selectable: true },
                    { id: "retired-active", label: "Retired Active", selectable: false },
                ]}
                current_summarization_model="retired-active"
                current_classification_model="retired-active"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByTestId("btn-remove-model-model-a")).toBeEnabled();
        expect(screen.getByTestId("btn-remove-model-model-b")).toBeEnabled();
        unmount();

        render(
            <LlmSettings
                supported_models={[
                    { id: "model-a", label: "Model A", selectable: true },
                    { id: "retired-active", label: "Retired Active", selectable: false },
                ]}
                current_summarization_model="retired-active"
                current_classification_model="retired-active"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByTestId("btn-remove-model-model-a")).toBeDisabled();
    });

    it("defensively resets unsaved summarization and classification selections and reasoning efforts if handleRemoveModel is triggered", () => {
        const modelsWithReasoning = [
            { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
            { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true, supports_reasoning: false },
            { id: "openai/o3-mini", label: "o3-mini", selectable: true, supports_reasoning: true },
        ];

        render(
            <LlmSettings
                supported_models={modelsWithReasoning}
                available_openrouter_models={[]}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summarization_reasoning_effort=""
                current_classification_reasoning_effort=""
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.change(screen.getByTestId("summarization-model-select"), {
            target: { value: "openai/o3-mini" },
        });
        fireEvent.change(screen.getByTestId("classification-model-select"), {
            target: { value: "openai/o3-mini" },
        });

        const summarizationReasoning = screen.getByLabelText("Summarization model reasoning level");
        fireEvent.change(summarizationReasoning, { target: { value: "high" } });
        const classificationReasoning = screen.getByLabelText("Testimony classification model reasoning level");
        fireEvent.change(classificationReasoning, { target: { value: "medium" } });

        setDataMock.mockClear();

        const removeButton = screen.getByTestId("btn-remove-model-openai/o3-mini");
        expect(removeButton).toBeDisabled();

        const propsKey = Object.keys(removeButton).find((key) => key.startsWith("__reactProps$"));
        expect(propsKey).toBeDefined();
        act(() => {
            (removeButton as unknown as Record<string, { onClick?: () => void }>)[propsKey!].onClick?.();
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summarization_model", "claude-haiku-5-5");
        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summarization_reasoning_effort", "");
        expect(setDataMock).toHaveBeenCalledWith("admin_setting.classification_model", "claude-sonnet-5-5");
        expect(setDataMock).toHaveBeenCalledWith("admin_setting.classification_reasoning_effort", "");

        expect(routerDeleteMock).toHaveBeenCalledWith(
            "/admin/llm_settings/remove_model",
            expect.objectContaining({
                data: { model_id: "openai/o3-mini" },
                preserveScroll: true,
            }),
        );
    });

    it("renders Combobox for available OpenRouter models and dispatches router.post to add a model", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const addSelect = screen.getByTestId("add-openrouter-model-select");
        fireEvent.change(addSelect, { target: { value: "deepseek/deepseek-chat" } });

        const addBtn = screen.getByTestId("btn-add-openrouter-model");
        expect(addBtn).toBeEnabled();
        fireEvent.click(addBtn);

        expect(routerPostMock).toHaveBeenCalledWith(
            "/admin/llm_settings/add_model",
            { model_id: "deepseek/deepseek-chat" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("clears selectedModelToAdd and disables Add model button when a poll removes the selected candidate from available_openrouter_models", () => {
        const { rerender } = render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const addSelect = screen.getByTestId("add-openrouter-model-select");
        fireEvent.change(addSelect, { target: { value: "deepseek/deepseek-chat" } });

        const addBtn = screen.getByTestId("btn-add-openrouter-model");
        expect(addBtn).toBeEnabled();

        rerender(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={[
                    { id: "meta-llama/llama-3.3-70b-instruct", label: "Meta: Llama 3.3 70B Instruct" },
                ]}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(addBtn).toBeDisabled();
    });

    it("dispatches router.post when clicking Refresh OpenRouter models button", () => {
        render(
            <LlmSettings
                supported_models={supportedModels}
                available_openrouter_models={availableOpenRouterModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.click(screen.getByTestId("btn-refresh-openrouter-models"));

        expect(routerPostMock).toHaveBeenCalledWith(
            "/admin/llm_settings/refresh_models",
            {},
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("renders reasoning level selector for reasoning-capable models and updates form data", () => {
        const modelsWithReasoning = [
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", selectable: true, supports_reasoning: true },
            { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
        ];

        render(
            <LlmSettings
                supported_models={modelsWithReasoning}
                current_summarization_model="Gemini Argon Latest"
                current_classification_model="claude-haiku-5-5"
                current_summarization_reasoning_effort="low"
                current_classification_reasoning_effort=""
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const summarizationReasoning = screen.getByLabelText(
            "Summarization model reasoning level",
        ) as HTMLSelectElement;
        expect(summarizationReasoning).toBeInTheDocument();
        expect(summarizationReasoning.value).toBe("low");

        fireEvent.change(summarizationReasoning, { target: { value: "high" } });
        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summarization_reasoning_effort", "high");

        expect(screen.queryByLabelText("Testimony classification model reasoning level")).toBeNull();
    });

    it("resets summarization reasoning effort to empty string when selecting a non-reasoning model", () => {
        const models = [
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", selectable: true, supports_reasoning: true },
            { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
        ];

        render(
            <LlmSettings
                supported_models={models}
                current_summarization_model="Gemini Argon Latest"
                current_classification_model="claude-haiku-5-5"
                current_summarization_reasoning_effort="high"
                current_classification_reasoning_effort=""
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.change(screen.getByTestId("summarization-model-select"), {
            target: { value: "claude-haiku-5-5" },
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summarization_model", "claude-haiku-5-5");
        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summarization_reasoning_effort", "");
    });

    it("resets classification reasoning effort to empty string when selecting a non-reasoning model", () => {
        const models = [
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", selectable: true, supports_reasoning: true },
            { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
        ];

        render(
            <LlmSettings
                supported_models={models}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="Gemini Argon Latest"
                current_summarization_reasoning_effort=""
                current_classification_reasoning_effort="high"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.change(screen.getByTestId("classification-model-select"), {
            target: { value: "claude-haiku-5-5" },
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.classification_model", "claude-haiku-5-5");
        expect(setDataMock).toHaveBeenCalledWith("admin_setting.classification_reasoning_effort", "");
    });

    it("does not reset reasoning effort when switching to another reasoning-capable model", () => {
        const modelsWithMultipleReasoning = [
            { id: "Gemini Argon Latest", label: "Gemini Argon Latest", selectable: true, supports_reasoning: true },
            { id: "openai/o3-mini", label: "o3-mini", selectable: true, supports_reasoning: true },
            { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
        ];

        render(
            <LlmSettings
                supported_models={modelsWithMultipleReasoning}
                current_summarization_model="Gemini Argon Latest"
                current_classification_model="Gemini Argon Latest"
                current_summarization_reasoning_effort="high"
                current_classification_reasoning_effort="high"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.change(screen.getByTestId("summarization-model-select"), {
            target: { value: "openai/o3-mini" },
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.summarization_model", "openai/o3-mini");
        expect(setDataMock).not.toHaveBeenCalledWith("admin_setting.summarization_reasoning_effort", "");

        fireEvent.change(screen.getByTestId("classification-model-select"), {
            target: { value: "openai/o3-mini" },
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.classification_model", "openai/o3-mini");
        expect(setDataMock).not.toHaveBeenCalledWith("admin_setting.classification_reasoning_effort", "");
    });
});

describe("Admin LLM Settings — specialized decision and extraction models", () => {
    const defaultModels = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
        { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
    ];
    const decisionModels = [
        { id: "Jev Latest", label: "Jev Latest", selectable: true, supports_reasoning: false },
        {
            id: "Perplexity Decider Latest",
            label: "Perplexity Decider Latest",
            selectable: true,
            supports_reasoning: false,
        },
    ];
    const extractionModels = [
        {
            id: "ScaleDown Extract Latest",
            label: "ScaleDown Extract Latest",
            selectable: true,
            supports_reasoning: false,
        },
        { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true, supports_reasoning: false },
    ];

    it("renders decision and extraction model pickers with their descriptions and values", () => {
        render(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByText("Decision model")).toBeInTheDocument();
        expect(
            screen.getByText(
                "Scores structured choice, yes/no, and scale questions via OpenRouter Decisions API (such as ScaleDown Classify Latest or Jev Latest).",
            ),
        ).toBeInTheDocument();
        expect(screen.getByText("Extraction model")).toBeInTheDocument();
        expect(
            screen.getByText(
                "Extracts structured organization, role, and quote spans from testimony and news articles (such as ScaleDown Extract Latest).",
            ),
        ).toBeInTheDocument();
        expect(screen.getByTestId("decision-model-value")).toHaveTextContent("Jev Latest");
        expect(screen.getByTestId("extraction-model-value")).toHaveTextContent("ScaleDown Extract Latest");
        expect(screen.queryByLabelText(/Decision model reasoning level/i)).not.toBeInTheDocument();
        expect(screen.queryByLabelText(/Extraction model reasoning level/i)).not.toBeInTheDocument();
    });

    it("enables save and submits transformed payload with changed decision model and expected baseline", () => {
        render(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        const saveButton = screen.getByRole("button", { name: "Save settings" });
        expect(saveButton).toBeDisabled();

        fireEvent.change(screen.getByTestId("decision-model-select"), {
            target: { value: "Perplexity Decider Latest" },
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.decision_model", "Perplexity Decider Latest");
        expect(saveButton).not.toBeDisabled();

        fireEvent.submit(screen.getByTestId("llm-settings-form"));

        expect(formTransformMock).toHaveBeenCalledTimes(1);
        const transformFn = formTransformMock.mock.calls[0][0] as () => {
            admin_setting: Record<string, unknown>;
        };
        const payload = transformFn();
        expect(payload).toEqual({
            admin_setting: {
                decision_model: "Perplexity Decider Latest",
                expected: {
                    decision_model: "Jev Latest",
                },
            },
        });
        expect(formPatchMock).toHaveBeenCalledWith(
            "/admin/llm_settings",
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("enables save and submits transformed payload with changed extraction model and expected baseline", () => {
        render(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.change(screen.getByTestId("extraction-model-select"), {
            target: { value: "claude-haiku-5-5" },
        });

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.extraction_model", "claude-haiku-5-5");
        fireEvent.submit(screen.getByTestId("llm-settings-form"));

        expect(formTransformMock).toHaveBeenCalledTimes(1);
        const transformFn = formTransformMock.mock.calls[0][0] as () => {
            admin_setting: Record<string, unknown>;
        };
        const payload = transformFn();
        expect(payload).toEqual({
            admin_setting: {
                extraction_model: "claude-haiku-5-5",
                expected: {
                    extraction_model: "ScaleDown Extract Latest",
                },
            },
        });
    });

    it("renders validation errors for decision and extraction models in nested or dotted format", () => {
        mockErrors = {
            "admin_setting.decision_model": "is not an allowed decision model",
            extraction_model: "is not an allowed extraction model",
        };

        render(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByText("is not an allowed decision model")).toBeInTheDocument();
        expect(screen.getByText("is not an allowed extraction model")).toBeInTheDocument();
    });

    it("displays changed elsewhere warning when decision or extraction model is modified by another admin", () => {
        const { rerender } = render(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();

        rerender(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Perplexity Decider Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={{ name: "Other Admin" }}
                updated_at="2026-07-27T01:00:00Z"
            />,
        );

        expect(screen.getByTestId("llm-settings-changed-elsewhere")).toBeInTheDocument();
        fireEvent.click(screen.getByTestId("btn-llm-settings-load-current"));
        expect(setDataMock).toHaveBeenCalledWith(
            "admin_setting",
            expect.objectContaining({
                decision_model: "Perplexity Decider Latest",
            }),
        );
    });

    it("resets unsaved decision or extraction model selection if removed from supported options by a poll", () => {
        const { rerender } = render(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        fireEvent.change(screen.getByTestId("decision-model-select"), {
            target: { value: "Perplexity Decider Latest" },
        });

        rerender(
            <LlmSettings
                supported_models={defaultModels}
                supported_decision_models={[{ id: "Jev Latest", label: "Jev Latest", selectable: true }]}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-haiku-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(setDataMock).toHaveBeenCalledWith("admin_setting.decision_model", "Jev Latest");
    });

    it("marks models active and disables removal when assigned to decision or extraction model", () => {
        const models = [
            { id: "Jev Latest", label: "Jev Latest", selectable: true },
            { id: "ScaleDown Extract Latest", label: "ScaleDown Extract Latest", selectable: true },
            { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
            { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
        ];

        render(
            <LlmSettings
                supported_models={models}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_decision_model="Jev Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
            />,
        );

        expect(screen.getByTestId("btn-remove-model-Jev Latest")).toBeDisabled();
        expect(screen.getByTestId("btn-remove-model-ScaleDown Extract Latest")).toBeDisabled();
    });
});

describe("LlmSettings Adversarial Scenarios", () => {
    type SupportedModel = {
        id: string;
        label: string;
        selectable: boolean;
        supports_reasoning?: boolean;
    };

    const defaultSupportedModels: SupportedModel[] = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
        { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
        { id: "ScaleDown Classify Latest", label: "ScaleDown Classify Latest", selectable: true },
        { id: "ScaleDown Extract Latest", label: "ScaleDown Extract Latest", selectable: true },
        { id: "Jev Latest", label: "Jev Latest", selectable: true },
        { id: "extra-candidate-model", label: "Extra Candidate Model", selectable: true },
    ];

    const decisionModels: SupportedModel[] = [
        { id: "ScaleDown Classify Latest", label: "ScaleDown Classify Latest", selectable: true },
        { id: "Jev Latest", label: "Jev Latest", selectable: true },
        { id: "Perplexity Decider Latest", label: "Perplexity Decider Latest", selectable: true },
        { id: "Perplexity Decider Flash Latest", label: "Perplexity Decider Flash Latest", selectable: true },
    ];

    const extractionModels: SupportedModel[] = [
        { id: "ScaleDown Extract Latest", label: "ScaleDown Extract Latest", selectable: true },
        { id: "claude-haiku-5-5", label: "Haiku 5.5", selectable: true },
        { id: "claude-sonnet-5-5", label: "Sonnet 5.5", selectable: true },
        { id: "extra-candidate-model", label: "Extra Candidate Model", selectable: true },
    ];

    const renderLlmSettings = (overrides = {}) =>
        render(
            <LlmSettings
                supported_models={defaultSupportedModels}
                supported_decision_models={decisionModels}
                supported_extraction_models={extractionModels}
                current_summarization_model="claude-haiku-5-5"
                current_classification_model="claude-sonnet-5-5"
                current_decision_model="ScaleDown Classify Latest"
                current_extraction_model="ScaleDown Extract Latest"
                current_summarization_reasoning_effort={null}
                current_classification_reasoning_effort={null}
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-27T00:00:00Z"
                {...overrides}
            />,
        );

    describe("LlmSettings Adversarial — Polling Option Reconciliation", () => {
        it("resets uncommitted decision model choice when background poll removes the option", () => {
            const { rerender } = renderLlmSettings();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Perplexity Decider Latest" },
            });

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={[
                        { id: "ScaleDown Classify Latest", label: "ScaleDown Classify Latest", selectable: true },
                        { id: "Jev Latest", label: "Jev Latest", selectable: true },
                    ]}
                    supported_extraction_models={extractionModels}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={null}
                    updated_at="2026-07-27T00:00:00Z"
                />,
            );

            expect(setDataMock).toHaveBeenCalledWith("admin_setting.decision_model", "ScaleDown Classify Latest");
        });

        it("resets uncommitted extraction model choice when background poll removes the option", () => {
            const { rerender } = renderLlmSettings();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "extra-candidate-model" },
            });

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels}
                    supported_extraction_models={[
                        { id: "ScaleDown Extract Latest", label: "ScaleDown Extract Latest", selectable: true },
                    ]}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={null}
                    updated_at="2026-07-27T00:00:00Z"
                />,
            );

            expect(setDataMock).toHaveBeenCalledWith("admin_setting.extraction_model", "ScaleDown Extract Latest");
        });

        it("survives rapid multi-cycle polling updates without corrupting committed state", () => {
            const { rerender } = renderLlmSettings();

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels.slice(0, 3)}
                    supported_extraction_models={extractionModels.slice(0, 3)}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={null}
                    updated_at="2026-07-27T00:01:00Z"
                />,
            );

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels.slice(0, 2)}
                    supported_extraction_models={extractionModels.slice(0, 2)}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={null}
                    updated_at="2026-07-27T00:02:00Z"
                />,
            );

            expect(setDataMock).not.toHaveBeenCalledWith("admin_setting.decision_model", expect.anything());
            expect(setDataMock).not.toHaveBeenCalledWith("admin_setting.extraction_model", expect.anything());
        });

        it("reconciles both decision and extraction choices when a single poll drops both uncommitted options", () => {
            const { rerender } = renderLlmSettings();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Perplexity Decider Flash Latest" },
            });
            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "extra-candidate-model" },
            });

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={[
                        { id: "ScaleDown Classify Latest", label: "ScaleDown Classify Latest", selectable: true },
                    ]}
                    supported_extraction_models={[
                        { id: "ScaleDown Extract Latest", label: "ScaleDown Extract Latest", selectable: true },
                    ]}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={null}
                    updated_at="2026-07-27T00:03:00Z"
                />,
            );

            expect(setDataMock).toHaveBeenCalledWith("admin_setting.decision_model", "ScaleDown Classify Latest");
            expect(setDataMock).toHaveBeenCalledWith("admin_setting.extraction_model", "ScaleDown Extract Latest");
        });
    });

    describe("LlmSettings Adversarial — Concurrency Detection and Value Adoption", () => {
        it("triggers changedElsewhere alert specifically when current_decision_model changes externally", () => {
            const { rerender } = renderLlmSettings();

            expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels}
                    supported_extraction_models={extractionModels}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="Jev Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={{ name: "Colleague Admin" }}
                    updated_at="2026-07-27T01:00:00Z"
                />,
            );

            expect(screen.getByTestId("llm-settings-changed-elsewhere")).toBeInTheDocument();
            expect(screen.getByTestId("llm-settings-changed-elsewhere")).toHaveTextContent(
                "Another admin changed these settings. The models below are the previous ones.",
            );

            fireEvent.click(screen.getByTestId("btn-llm-settings-load-current"));

            expect(setDataMock).toHaveBeenCalledWith(
                "admin_setting",
                expect.objectContaining({
                    decision_model: "Jev Latest",
                    extraction_model: "ScaleDown Extract Latest",
                }),
            );
            expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();
        });

        it("triggers changedElsewhere alert specifically when current_extraction_model changes externally", () => {
            const { rerender } = renderLlmSettings();

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels}
                    supported_extraction_models={extractionModels}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="claude-sonnet-5-5"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={{ name: "Colleague Admin" }}
                    updated_at="2026-07-27T01:00:00Z"
                />,
            );

            expect(screen.getByTestId("llm-settings-changed-elsewhere")).toBeInTheDocument();
            fireEvent.click(screen.getByTestId("btn-llm-settings-load-current"));

            expect(setDataMock).toHaveBeenCalledWith(
                "admin_setting",
                expect.objectContaining({
                    decision_model: "ScaleDown Classify Latest",
                    extraction_model: "claude-sonnet-5-5",
                }),
            );
            expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();
        });

        it("presents refusal notice and discard button when external update conflicts with local uncommitted edits", () => {
            const { rerender } = renderLlmSettings();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Perplexity Decider Latest" },
            });

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels}
                    supported_extraction_models={extractionModels}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="Jev Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={{ name: "Colleague Admin" }}
                    updated_at="2026-07-27T01:30:00Z"
                />,
            );

            const alert = screen.getByTestId("llm-settings-changed-elsewhere");
            expect(alert).toHaveTextContent(
                "Another admin changed these settings while you were choosing. Saving now will be refused.",
            );

            const loadButton = screen.getByTestId("btn-llm-settings-load-current");
            expect(loadButton).toHaveTextContent("Discard my choice and load the current settings");

            fireEvent.click(loadButton);

            expect(setDataMock).toHaveBeenCalledWith(
                "admin_setting",
                expect.objectContaining({
                    decision_model: "Jev Latest",
                }),
            );
            expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();
        });

        it("does not trigger changedElsewhere when unrelated metadata updates while models remain identical", () => {
            const { rerender } = renderLlmSettings();

            rerender(
                <LlmSettings
                    supported_models={defaultSupportedModels}
                    supported_decision_models={decisionModels}
                    supported_extraction_models={extractionModels}
                    current_summarization_model="claude-haiku-5-5"
                    current_classification_model="claude-sonnet-5-5"
                    current_decision_model="ScaleDown Classify Latest"
                    current_extraction_model="ScaleDown Extract Latest"
                    current_summarization_reasoning_effort={null}
                    current_classification_reasoning_effort={null}
                    current_summary_batch_enabled={false}
                    updated_by={{ name: "Same Admin" }}
                    updated_at="2026-07-27T02:00:00Z"
                />,
            );

            expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();
        });
    });

    describe("LlmSettings Adversarial — Conditional Payload Generation", () => {
        it("generates payload with ONLY decision_model and its expected baseline when only decision model changes", () => {
            renderLlmSettings();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Jev Latest" },
            });

            fireEvent.submit(screen.getByTestId("llm-settings-form"));

            expect(formTransformMock).toHaveBeenCalledTimes(1);
            const transformFn = formTransformMock.mock.calls[0][0] as () => {
                admin_setting: Record<string, unknown>;
            };
            const payload = transformFn();

            expect(payload).toEqual({
                admin_setting: {
                    decision_model: "Jev Latest",
                    expected: {
                        decision_model: "ScaleDown Classify Latest",
                    },
                },
            });

            const rootKeys = Object.keys(payload.admin_setting);
            expect(rootKeys.sort()).toEqual(["decision_model", "expected"]);

            const expectedKeys = Object.keys(payload.admin_setting.expected as Record<string, unknown>);
            expect(expectedKeys).toEqual(["decision_model"]);
        });

        it("generates payload with ONLY extraction_model and its expected baseline when only extraction model changes", () => {
            renderLlmSettings();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "claude-haiku-5-5" },
            });

            fireEvent.submit(screen.getByTestId("llm-settings-form"));

            expect(formTransformMock).toHaveBeenCalledTimes(1);
            const transformFn = formTransformMock.mock.calls[0][0] as () => {
                admin_setting: Record<string, unknown>;
            };
            const payload = transformFn();

            expect(payload).toEqual({
                admin_setting: {
                    extraction_model: "claude-haiku-5-5",
                    expected: {
                        extraction_model: "ScaleDown Extract Latest",
                    },
                },
            });

            const rootKeys = Object.keys(payload.admin_setting);
            expect(rootKeys.sort()).toEqual(["expected", "extraction_model"]);

            const expectedKeys = Object.keys(payload.admin_setting.expected as Record<string, unknown>);
            expect(expectedKeys).toEqual(["extraction_model"]);
        });

        it("generates payload containing both specialized models when both are modified without leaking standard fields", () => {
            renderLlmSettings();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Perplexity Decider Latest" },
            });
            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "extra-candidate-model" },
            });

            fireEvent.submit(screen.getByTestId("llm-settings-form"));

            const transformFn = formTransformMock.mock.calls[0][0] as () => {
                admin_setting: Record<string, unknown>;
            };
            const payload = transformFn();

            expect(payload).toEqual({
                admin_setting: {
                    decision_model: "Perplexity Decider Latest",
                    extraction_model: "extra-candidate-model",
                    expected: {
                        decision_model: "ScaleDown Classify Latest",
                        extraction_model: "ScaleDown Extract Latest",
                    },
                },
            });

            const rootKeys = Object.keys(payload.admin_setting);
            expect(rootKeys.sort()).toEqual(["decision_model", "expected", "extraction_model"]);

            const expectedKeys = Object.keys(payload.admin_setting.expected as Record<string, unknown>);
            expect(expectedKeys).toEqual(["decision_model", "extraction_model"]);
        });
    });

    describe("LlmSettings Adversarial — Dirty Tracking Accuracy and Revert Behavior", () => {
        it("resets isDirty to false and disables Save button when decision model is reverted to baseline", () => {
            renderLlmSettings();

            const saveButton = screen.getByRole("button", { name: /save settings/i });
            expect(saveButton).toBeDisabled();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Jev Latest" },
            });
            expect(saveButton).toBeEnabled();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "ScaleDown Classify Latest" },
            });
            expect(saveButton).toBeDisabled();

            fireEvent.submit(screen.getByTestId("llm-settings-form"));
            expect(formPatchMock).not.toHaveBeenCalled();
        });

        it("resets isDirty to false and disables Save button when extraction model is reverted to baseline", () => {
            renderLlmSettings();

            const saveButton = screen.getByRole("button", { name: /save settings/i });
            expect(saveButton).toBeDisabled();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "claude-haiku-5-5" },
            });
            expect(saveButton).toBeEnabled();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "ScaleDown Extract Latest" },
            });
            expect(saveButton).toBeDisabled();
        });

        it("tracks multi-field dirty state correctly during step-by-step reverts", () => {
            renderLlmSettings();

            const saveButton = screen.getByRole("button", { name: /save settings/i });
            expect(saveButton).toBeDisabled();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Jev Latest" },
            });
            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "claude-haiku-5-5" },
            });
            expect(saveButton).toBeEnabled();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "ScaleDown Classify Latest" },
            });
            expect(saveButton).toBeEnabled();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "ScaleDown Extract Latest" },
            });
            expect(saveButton).toBeDisabled();
        });
    });

    describe("LlmSettings Adversarial — Offered Models Removal Safety Invariants", () => {
        it("disables removal button when an offered model is saved as decision or extraction model", () => {
            renderLlmSettings();

            const removeDecisionBtn = screen.getByTestId("btn-remove-model-ScaleDown Classify Latest");
            const removeExtractionBtn = screen.getByTestId("btn-remove-model-ScaleDown Extract Latest");
            const removeExtraBtn = screen.getByTestId("btn-remove-model-extra-candidate-model");

            expect(removeDecisionBtn).toBeDisabled();
            expect(removeExtractionBtn).toBeDisabled();
            expect(removeExtraBtn).toBeEnabled();
        });

        it("dynamically disables removal of an offered model when selected in uncommitted decision form state", () => {
            renderLlmSettings();

            const removeJevBtn = screen.getByTestId("btn-remove-model-Jev Latest");
            expect(removeJevBtn).toBeEnabled();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Jev Latest" },
            });
            expect(removeJevBtn).toBeDisabled();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "ScaleDown Classify Latest" },
            });
            expect(removeJevBtn).toBeEnabled();
        });

        it("dynamically disables removal of an offered model when selected in uncommitted extraction form state", () => {
            renderLlmSettings();

            const removeExtraBtn = screen.getByTestId("btn-remove-model-extra-candidate-model");
            expect(removeExtraBtn).toBeEnabled();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "extra-candidate-model" },
            });
            expect(removeExtraBtn).toBeDisabled();

            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "ScaleDown Extract Latest" },
            });
            expect(removeExtraBtn).toBeEnabled();
        });

        it("defensively resets uncommitted decision and extraction model choices when removal is invoked", () => {
            renderLlmSettings();

            fireEvent.change(screen.getByTestId("decision-model-select"), {
                target: { value: "Jev Latest" },
            });
            fireEvent.change(screen.getByTestId("extraction-model-select"), {
                target: { value: "extra-candidate-model" },
            });

            const removeJevBtn = screen.getByTestId("btn-remove-model-Jev Latest");
            const removeExtraBtn = screen.getByTestId("btn-remove-model-extra-candidate-model");
            expect(removeJevBtn).toBeDisabled();
            expect(removeExtraBtn).toBeDisabled();

            setDataMock.mockClear();

            const jevPropsKey = Object.keys(removeJevBtn).find((key) => key.startsWith("__reactProps$"));
            expect(jevPropsKey).toBeDefined();
            act(() => {
                (removeJevBtn as unknown as Record<string, { onClick?: () => void }>)[jevPropsKey!].onClick?.();
            });

            expect(setDataMock).toHaveBeenCalledWith("admin_setting.decision_model", "ScaleDown Classify Latest");
            expect(routerDeleteMock).toHaveBeenCalledWith(
                "/admin/llm_settings/remove_model",
                expect.objectContaining({
                    data: { model_id: "Jev Latest" },
                }),
            );

            const firstDeleteOptions = routerDeleteMock.mock.calls[0][1] as { onFinish?: () => void } | undefined;
            act(() => {
                firstDeleteOptions?.onFinish?.();
            });

            setDataMock.mockClear();
            routerDeleteMock.mockClear();

            const extraPropsKey = Object.keys(removeExtraBtn).find((key) => key.startsWith("__reactProps$"));
            expect(extraPropsKey).toBeDefined();
            act(() => {
                (removeExtraBtn as unknown as Record<string, { onClick?: () => void }>)[extraPropsKey!].onClick?.();
            });

            expect(setDataMock).toHaveBeenCalledWith("admin_setting.extraction_model", "ScaleDown Extract Latest");
            expect(routerDeleteMock).toHaveBeenCalledWith(
                "/admin/llm_settings/remove_model",
                expect.objectContaining({
                    data: { model_id: "extra-candidate-model" },
                }),
            );
        });
    });
});
