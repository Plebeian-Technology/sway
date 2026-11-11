import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const pageProps: { current: Record<string, unknown> } = { current: {} };
const routerPost = vi.fn<(url: string, data?: unknown, options?: unknown) => void>();
const routerPatch = vi.fn<(url: string, data?: unknown, options?: unknown) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: [string, unknown?, unknown?]) => routerPost(...args),
        patch: (...args: [string, unknown?, unknown?]) => routerPatch(...args),
    },
    usePage: () => ({ props: pageProps.current }),
    useForm: () => ({
        data: {},
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        post: vi.fn<(url?: string, options?: Record<string, unknown>) => void>(),
        processing: false,
        errors: {},
        reset: vi.fn<(...keys: string[]) => void>(),
        transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
    }),
    Link: ({ children, href, ...rest }: { children: React.ReactNode; href: string }) => (
        <a href={href} {...rest}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(...args: unknown[]) => string>() }));

import BillCreatorLlmSummary from "app/frontend/components/admin/creator/BillCreatorLlmSummary";
import LlmSummaryCompletedView from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedView";
import SummaryModelPicker from "app/frontend/components/admin/creator/llm-summary/SummaryModelPicker";
import { IBillLlmProvisioning, ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";

const provisioning = (): IBillLlmProvisioning => ({
    generation_status: "completed",
    generation_error: null,
    llm_summary: "A summary.",
    llm_full_breakdown: "## Section 1\nWhat it does.",
    supplemental_testimony: null,
    draft_org_positions: null,
    stale: false,
    reclaimable: false,
    paste_owns_summary_run: false,
    stale_change_kind: null,
    stale_change_at: null,
    llm_generated_at: null,
    llm_provider: "claude",
    has_testimony: false,
    testimony_attachments: [],
    citations_valid: true,
    invalid_citations: [],
});

const renderView = (onConfirmRegenerate: () => void, modelOptions: ISummaryModelOption[] = [], selectedModel = "") =>
    render(
        <LlmSummaryCompletedView
            billId={1}
            provisioning={provisioning()}
            publishedSummary="The published summary."
            isBillPipelineRunning={false}
            runLoading={false}
            isRegenerating={false}
            abandoned={false}
            onConfirmRegenerate={onConfirmRegenerate}
            modelOptions={modelOptions}
            selectedModel={selectedModel}
            onModelChange={() => {}}
        />,
    );

beforeEach(() => {
    sessionStorage.clear();
    pageProps.current = {};
    vi.clearAllMocks();
});

describe("the summary tab's per-run model choice", () => {
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    const options: ISummaryModelOption[] = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5" },
        { id: "claude-sonnet-5-5", label: "Sonnet 5.5" },
        { id: "claude-opus-5-5", label: "Opus 5.5" },
    ];

    it("shows the model it was given as the current choice", () => {
        renderView(vi.fn<() => void>(), options, "claude-sonnet-5-5");

        expect(screen.getByTestId("select-summary-model").textContent).toContain("Sonnet 5.5");
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    it("reads as the standing default when the current model is not one it offers", () => {
        renderView(vi.fn<() => void>(), options, "claude-retired-1");

        expect(screen.getByTestId("select-summary-model").textContent).toContain("Standing default");
    });

    // A page served before this prop existed, or a partial reload that dropped it.
    // The picker carries no visible label — the option text says what it is — so
    // the accessible name is the only thing naming it for a screen reader.
    it("names itself for a screen reader", () => {
        renderView(vi.fn<() => void>(), options, "claude-sonnet-5-5");

        expect(screen.getByLabelText("Model for this run")).toBeTruthy();
    });

    it("renders no picker when the server sent no options", () => {
        renderView(vi.fn<() => void>());

        expect(screen.queryByTestId("select-summary-model")).toBeNull();
    });

    it("starts the regeneration the confirm dialog confirms", () => {
        const onConfirmRegenerate = vi.fn<() => void>();
        renderView(onConfirmRegenerate, options, "claude-opus-5-5");

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(onConfirmRegenerate).toHaveBeenCalledTimes(1);
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The confirm dialog names the model]]
    it("names the model on the last screen before the run starts", () => {
        renderView(vi.fn<() => void>(), options, "claude-opus-5-5");

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));

        expect(screen.getByTestId("confirm-dialog-model").textContent).toBe("This run uses Opus 5.5.");
    });

    it("keeps the warning about the draft it replaces beside that line", () => {
        renderView(vi.fn<() => void>(), options, "claude-opus-5-5");

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));

        expect(screen.getByTestId("confirmation-dialog").textContent ?? "").toContain(
            "This will replace the model's draft summary. The published summary below is not changed by this.",
        );
    });

    it("says the run uses the standing default rather than printing an id it cannot name", () => {
        renderView(vi.fn<() => void>(), options, "claude-retired-1");

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));

        const line = screen.getByTestId("confirm-dialog-model").textContent ?? "";
        expect(line).toBe("This run uses the standing default model.");
        expect(line).not.toContain("claude-retired-1");
    });

    it("puts the run controls under the Public summary box, above the section breakdown", () => {
        renderView(vi.fn<() => void>());

        const order = Array.from(
            document.querySelectorAll(
                "[data-testid='textarea-llm-summary'], [data-testid='btn-save-summary'], " +
                    "[data-testid='btn-regenerate-summary'], [data-testid='btn-paste-summary-completed'], " +
                    "[data-testid='btn-toggle-breakdown']",
            ),
        ).map((el) => el.getAttribute("data-testid"));

        expect(order).toEqual([
            "textarea-llm-summary",
            "btn-save-summary",
            "btn-regenerate-summary",
            "btn-paste-summary-completed",
            "btn-toggle-breakdown",
        ]);
    });

    describe("candidate OpenRouter model choices", () => {
        const candidateOptions: ISummaryModelOption[] = [
            { id: "claude-haiku-5-5", label: "Haiku 5.5" },
            { id: "claude-sonnet-5-5", label: "Sonnet 5.5" },
            { id: "claude-opus-5-5", label: "Opus 5.5" },
            { id: "Deepseek Pro Latest", label: "Deepseek Pro Latest" },
            { id: "Deepseek Flash Latest", label: "Deepseek Flash Latest" },
            { id: "OpenRouter Auto", label: "OpenRouter Auto" },
        ];

        it("displays candidate OpenRouter choices as the current choice in the picker", () => {
            const openRouterChoices = ["Deepseek Pro Latest", "Deepseek Flash Latest", "OpenRouter Auto"];
            for (const choice of openRouterChoices) {
                const { unmount } = renderView(vi.fn<() => void>(), candidateOptions, choice);
                expect(screen.getByTestId("select-summary-model").textContent).toContain(choice);
                unmount();
            }

            // Flat display: no optgroup or provider badges in the container
            renderView(vi.fn<() => void>(), candidateOptions, "Deepseek Pro Latest");
            expect(screen.queryByRole("group")).toBeNull();
            expect(screen.queryByText(/Anthropic/i)).toBeNull();
            expect(screen.queryByText(/Provider/i)).toBeNull();
        });

        it("displays the selected OpenRouter choice in the confirm dialog", () => {
            const openRouterChoices = [
                { id: "Deepseek Pro Latest", expected: "This run uses Deepseek Pro Latest." },
                { id: "Deepseek Flash Latest", expected: "This run uses Deepseek Flash Latest." },
                { id: "OpenRouter Auto", expected: "This run uses OpenRouter Auto." },
            ];

            for (const choice of openRouterChoices) {
                const { unmount } = renderView(vi.fn<() => void>(), candidateOptions, choice.id);

                fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
                expect(screen.getByTestId("confirm-dialog-model").textContent).toBe(choice.expected);

                unmount();
            }
        });

        it("displays arbitrary dynamic OpenRouter model options in the picker and confirm dialog", () => {
            const dynamicOptions: ISummaryModelOption[] = [
                ...candidateOptions,
                { id: "openai/gpt-4o", label: "OpenAI: GPT-4o" },
                { id: "google/gemini-2.5-flash", label: "Google: Gemini 2.5 Flash" },
            ];

            const { unmount } = renderView(vi.fn<() => void>(), dynamicOptions, "openai/gpt-4o");
            expect(screen.getByTestId("select-summary-model").textContent).toContain("OpenAI: GPT-4o");

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            expect(screen.getByTestId("confirm-dialog-model").textContent).toBe("This run uses OpenAI: GPT-4o.");
            unmount();
        });

        it("renders a searchable combobox with search input in the popover", () => {
            const dynamicOptions: ISummaryModelOption[] = [
                ...candidateOptions,
                { id: "openai/gpt-4o", label: "OpenAI: GPT-4o" },
            ];
            renderView(vi.fn<() => void>(), dynamicOptions, "openai/gpt-4o");
            const trigger = screen.getByTestId("select-summary-model");
            fireEvent.click(trigger);
            expect(screen.getByPlaceholderText("Search models...")).toBeTruthy();
        });

        it("renders reasoning level selector when selected model supports reasoning", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];
            const onReasoningEffortChange = vi.fn<(effort: string) => void>();

            render(
                <SummaryModelPicker
                    modelOptions={reasoningOptions}
                    selectedModel="Gemini Argon Latest"
                    onModelChange={vi.fn<(model: string) => void>()}
                    selectedReasoningEffort="medium"
                    onReasoningEffortChange={onReasoningEffortChange}
                />,
            );

            const select = screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement;
            expect(select).toBeInTheDocument();
            expect(select).toHaveAttribute("aria-label", "Reasoning level for this run");
            expect(select.value).toBe("medium");

            const renderedOptions = Array.from(select.querySelectorAll("option")).map((o) => ({
                value: o.value,
                text: o.textContent,
            }));
            expect(renderedOptions).toEqual([
                { value: "", text: "Default" },
                { value: "low", text: "Low" },
                { value: "medium", text: "Medium" },
                { value: "high", text: "High" },
            ]);

            fireEvent.change(select, { target: { value: "high" } });
            expect(onReasoningEffortChange).toHaveBeenCalledWith("high");
        });

        it("does not render reasoning level selector when selected model does not support reasoning", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            render(
                <SummaryModelPicker
                    modelOptions={reasoningOptions}
                    selectedModel="claude-haiku-5-5"
                    onModelChange={vi.fn<(model: string) => void>()}
                />,
            );

            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();
        });

        it("resets reasoning effort when switching to a non-reasoning model and gates outbound payload", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "claude-haiku-5-5",
            };

            render(<BillCreatorLlmSummary />);

            fireEvent.click(screen.getByTestId("select-summary-model"));
            fireEvent.click(screen.getByRole("option", { name: "Gemini Argon Latest" }));

            const reasoningSelect = screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement;
            expect(reasoningSelect).toBeInTheDocument();
            fireEvent.change(reasoningSelect, { target: { value: "high" } });
            expect(reasoningSelect.value).toBe("high");

            fireEvent.click(screen.getByTestId("select-summary-model"));
            fireEvent.click(screen.getByRole("option", { name: "Haiku 5.5" }));

            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/42/regenerate_summary",
                {
                    summarization_model: "claude-haiku-5-5",
                },
                expect.any(Object),
            );

            fireEvent.click(screen.getByTestId("select-summary-model"));
            fireEvent.click(screen.getByRole("option", { name: "Gemini Argon Latest" }));

            const resetReasoningSelect = screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement;
            expect(resetReasoningSelect).toBeInTheDocument();
            expect(resetReasoningSelect.value).toBe("");
        });

        it("does not render reasoning level selector when selected model is unoffered even with selectedReasoningEffort", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            render(
                <SummaryModelPicker
                    modelOptions={reasoningOptions}
                    selectedModel="retired-unoffered-model"
                    onModelChange={vi.fn<(model: string) => void>()}
                    selectedReasoningEffort="high"
                />,
            );

            expect(screen.getByTestId("select-summary-model").textContent).toContain("Standing default");
            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();
        });

        it("resolves supports_reasoning consistently via offeredModel and does not forward reasoning_effort when sessionStorage holds an unoffered model ID", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            sessionStorage.setItem("sway.summaryModel.42", "retired-unoffered-model");

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "Gemini Argon Latest",
            };

            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("select-summary-model").textContent).toContain("Standing default");
            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

            expect(routerPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {}, expect.any(Object));
        });

        it("renders reasoning level selector and forwards reasoning_effort when sessionStorage holds an offered reasoning model even if standing default is non-reasoning", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            sessionStorage.setItem("sway.summaryModel.42", "Gemini Argon Latest");

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "claude-haiku-5-5",
            };

            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("select-summary-model").textContent).toContain("Gemini Argon Latest");
            const reasoningSelect = screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement;
            expect(reasoningSelect).toBeInTheDocument();

            fireEvent.change(reasoningSelect, { target: { value: "medium" } });
            expect(reasoningSelect.value).toBe("medium");

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/42/regenerate_summary",
                {
                    summarization_model: "Gemini Argon Latest",
                    reasoning_effort: "medium",
                },
                expect.any(Object),
            );
        });

        it("omits reasoning_effort when sessionStorage holds an offered non-reasoning model even if standing default is reasoning", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            sessionStorage.setItem("sway.summaryModel.42", "claude-haiku-5-5");

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "Gemini Argon Latest",
            };

            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("select-summary-model").textContent).toContain("Haiku 5.5");
            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/42/regenerate_summary",
                {
                    summarization_model: "claude-haiku-5-5",
                },
                expect.any(Object),
            );
        });

        it("omits both summarization_model and reasoning_effort when standing default is unoffered and sessionStorage is empty", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "retired-standing-default",
            };

            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("select-summary-model").textContent).toContain("Standing default");
            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

            expect(routerPost).toHaveBeenCalledWith("/bills/42/regenerate_summary", {}, expect.any(Object));
        });

        it("recalls selectedReasoningEffort per bill across remounts and resets per-bill state when switching bills", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
                { id: "claude-haiku-5-5", label: "Haiku 5.5", supports_reasoning: false },
            ];

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "Gemini Argon Latest",
            };

            const { unmount } = render(<BillCreatorLlmSummary />);

            const reasoningSelect = screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement;
            fireEvent.change(reasoningSelect, { target: { value: "high" } });
            expect(reasoningSelect.value).toBe("high");

            unmount();

            const remounted = render(<BillCreatorLlmSummary />);
            expect((screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement).value).toBe("high");

            pageProps.current = {
                bill: {
                    id: 99,
                    external_id: "CB-99",
                    summary: "Another bill summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "claude-haiku-5-5",
            };

            remounted.rerender(<BillCreatorLlmSummary />);
            expect(screen.getByTestId("select-summary-model").textContent).toContain("Haiku 5.5");
            expect(screen.queryByTestId("select-summary-reasoning-effort")).toBeNull();
        });

        it("initializes reasoning effort from current_summarization_reasoning_effort and sends 'default' when overridden to Default", () => {
            const reasoningOptions: ISummaryModelOption[] = [
                { id: "Opus Latest", label: "Opus Latest", supports_reasoning: true },
                { id: "Gemini Argon Latest", label: "Gemini Argon Latest", supports_reasoning: true },
            ];

            pageProps.current = {
                bill: {
                    id: 42,
                    external_id: "CB-42",
                    summary: "The published summary.",
                    bill_llm_provisioning: provisioning(),
                },
                summary_model_options: reasoningOptions,
                current_summarization_model: "Opus Latest",
                current_summarization_reasoning_effort: "high",
            };

            render(<BillCreatorLlmSummary />);

            const reasoningSelect = screen.getByTestId("select-summary-reasoning-effort") as HTMLSelectElement;
            expect(reasoningSelect.value).toBe("high");

            fireEvent.change(reasoningSelect, { target: { value: "" } });
            expect(reasoningSelect.value).toBe("");

            fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
            fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/42/regenerate_summary",
                {
                    summarization_model: "Opus Latest",
                    reasoning_effort: "default",
                },
                expect.any(Object),
            );
        });
    });
});
