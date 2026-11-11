import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href, ...rest }: { children: React.ReactNode; href: string; [key: string]: unknown }) => (
        <a href={href} {...(rest as Record<string, unknown>)}>
            {children}
        </a>
    ),
}));

import SystemPrompts from "app/frontend/pages/admin/SystemPrompts";

type PromptEntry = {
    id: string;
    label: string;
    purpose: string;
    builder: string;
    model: string;
    model_setting_label: string;
    system_prompt: string | null;
    character_count: number | null;
    unavailable_reason: string | null;
    sway_locale_name?: string | null;
};

const SUMMARY_TEXT =
    "You are a legislative analyst preparing a public summary of a bill.\n\n" +
    "Rules:\n" +
    "  - Two leading spaces  and a double space inside this line.\n";

const prompts: PromptEntry[] = [
    {
        id: "bill_summary_baltimore-maryland-united_states",
        label: "Bill summary",
        purpose: "Sent once per bill to produce the public summary.",
        builder: "BillSummaryPromptBuilder",
        model: "claude-opus-5-5",
        model_setting_label: "Summarization model",
        system_prompt: SUMMARY_TEXT,
        character_count: 8627,
        unavailable_reason: null,
        sway_locale_name: "baltimore-maryland-united_states",
    },
    {
        id: "bill_summary_congress-congress-united_states",
        label: "Bill summary",
        purpose: "Sent once per bill to produce the public summary.",
        builder: "BillSummaryPromptBuilder",
        model: "claude-opus-5-5",
        model_setting_label: "Summarization model",
        system_prompt: "You are an analyst for the United States Congress.",
        character_count: 8100,
        unavailable_reason: null,
        sway_locale_name: "congress-congress-united_states",
    },
    {
        id: "bill_summary_maryland-maryland-united_states",
        label: "Bill summary",
        purpose: "Sent once per bill to produce the public summary.",
        builder: "BillSummaryPromptBuilder",
        model: "claude-opus-5-5",
        model_setting_label: "Summarization model",
        system_prompt: null,
        character_count: null,
        unavailable_reason:
            "No summarization prompt is sent for maryland-maryland-united_states. There is no legislative body description in llm_bill_summarization_instructions for this locale. Run SeedLlmBillSummarizationInstruction to seed it.",
        sway_locale_name: "maryland-maryland-united_states",
    },
    {
        id: "bill_positions",
        label: "Organization positions",
        purpose: "Sent once per bill to draw organization positions out of the testimony.",
        builder: "BillPositionsPromptBuilder",
        model: "claude-opus-5-5",
        model_setting_label: "Summarization model",
        system_prompt: "You are a legislative analyst identifying organization positions.",
        character_count: 5410,
        unavailable_reason: null,
        sway_locale_name: null,
    },
    {
        id: "bill_categories",
        label: "Bill categories",
        purpose: "Sent by the category backfill.",
        builder: "BillCategoryPromptBuilder",
        model: "claude-opus-5-5",
        model_setting_label: "Summarization model",
        system_prompt: null,
        character_count: null,
        unavailable_reason: "No categorisation prompt is sent on this installation.",
        sway_locale_name: null,
    },
    {
        id: "testimony_classification",
        label: "Testimony attachment classification",
        purpose: "Sent per batch of hearing attachments.",
        builder: "Testimony::ClassificationPromptBuilder",
        model: "claude-haiku-5-5",
        model_setting_label: "Testimony classification model",
        system_prompt: "You are classifying attachments to a bill.",
        character_count: 4102,
        unavailable_reason: null,
        sway_locale_name: null,
    },
    {
        id: "testimony_source_kind",
        label: "Testimony source kind",
        purpose: "Sent per batch of cleaned testimony letters.",
        builder: "Testimony::SourceKindPromptBuilder",
        model: "claude-haiku-5-5",
        model_setting_label: "Testimony classification model",
        system_prompt: "You are deciding, for each letter of public testimony below.",
        character_count: 2048,
        unavailable_reason: null,
        sway_locale_name: null,
    },
];

const renderPage = (activeCategoryCount = 3) =>
    render(
        <SystemPrompts
            models={{ summarization: "claude-opus-5-5", classification: "claude-haiku-5-5" }}
            active_category_count={activeCategoryCount}
            llm_settings_path="/admin/llm_settings"
            prompts={prompts}
        />,
    );

const openTrigger = (name: RegExp) => fireEvent.click(screen.getByRole("button", { name }));

afterEach(cleanup);

describe("admin/SystemPrompts", () => {
    it("says these are the standing instruction only, not the whole request", () => {
        renderPage();

        expect(screen.getByRole("heading", { level: 1, name: "System prompts" })).toBeInTheDocument();
        expect(screen.getByText(/none of that appears here/i)).toBeInTheDocument();
        expect(screen.getByText(/change by a code change and a deploy/i)).toBeInTheDocument();
    });

    it("shows one trigger per prompt, with a character count or a not-sent badge", () => {
        renderPage();

        prompts.forEach((entry) => {
            const expectedName = entry.sway_locale_name
                ? new RegExp(`${entry.label}.*${entry.sway_locale_name}`)
                : new RegExp(entry.label);
            expect(screen.getByRole("button", { name: expectedName })).toBeInTheDocument();
        });

        expect(screen.getByText("8,627 characters")).toBeInTheDocument();
        expect(screen.getByText("8,100 characters")).toBeInTheDocument();
        expect(screen.getByText("5,410 characters")).toBeInTheDocument();
        expect(screen.getByText("4,102 characters")).toBeInTheDocument();
        expect(screen.getByText("2,048 characters")).toBeInTheDocument();
        expect(screen.getAllByText("Not sent")).toHaveLength(2);
    });

    it("renders a locale name badge for per-locale cards and none for singletons", () => {
        renderPage();

        expect(
            screen.getByTestId("system-prompt-locale-bill_summary_baltimore-maryland-united_states"),
        ).toHaveTextContent("baltimore-maryland-united_states");
        expect(
            screen.getByTestId("system-prompt-locale-bill_summary_congress-congress-united_states"),
        ).toHaveTextContent("congress-congress-united_states");
        expect(
            screen.getByTestId("system-prompt-locale-bill_summary_maryland-maryland-united_states"),
        ).toHaveTextContent("maryland-maryland-united_states");
        expect(screen.queryByTestId("system-prompt-locale-bill_positions")).toBeNull();
    });

    it("reveals only the prompt whose trigger was clicked", () => {
        renderPage();

        openTrigger(/baltimore-maryland-united_states/);

        const pre = screen.getByTestId("system-prompt-bill_summary_baltimore-maryland-united_states");
        expect(pre.textContent).toBe(SUMMARY_TEXT);
        expect(screen.getByText(/BillSummaryPromptBuilder/)).toBeInTheDocument();

        expect(screen.queryByTestId("system-prompt-bill_positions")).toBeNull();
        expect(screen.queryByTestId("system-prompt-testimony_classification")).toBeNull();
        expect(screen.queryByTestId("system-prompt-testimony_source_kind")).toBeNull();
        expect(screen.queryByTestId("system-prompt-bill_categories")).toBeNull();
    });

    it("shows not sent badge and unavailable alert for unseeded locale prompt", () => {
        renderPage();

        openTrigger(/maryland-maryland-united_states/);

        expect(
            screen.getByTestId("system-prompt-unavailable-bill_summary_maryland-maryland-united_states"),
        ).toHaveTextContent("llm_bill_summarization_instructions");
        expect(
            screen.getByTestId("system-prompt-unavailable-bill_summary_maryland-maryland-united_states"),
        ).toHaveTextContent("SeedLlmBillSummarizationInstruction");
        expect(screen.queryByTestId("system-prompt-bill_summary_maryland-maryland-united_states")).toBeNull();
    });

    it("opens and closes every prompt from one control", () => {
        renderPage();

        fireEvent.click(screen.getByRole("button", { name: "Expand all" }));

        expect(screen.getByTestId("system-prompt-bill_summary_baltimore-maryland-united_states")).toBeInTheDocument();
        expect(screen.getByTestId("system-prompt-bill_summary_congress-congress-united_states")).toBeInTheDocument();
        expect(
            screen.getByTestId("system-prompt-unavailable-bill_summary_maryland-maryland-united_states"),
        ).toBeInTheDocument();
        expect(screen.getByTestId("system-prompt-bill_positions")).toBeInTheDocument();
        expect(screen.getByTestId("system-prompt-testimony_classification")).toBeInTheDocument();
        expect(screen.getByTestId("system-prompt-testimony_source_kind")).toBeInTheDocument();
        expect(screen.getByTestId("system-prompt-unavailable-bill_categories")).toBeInTheDocument();

        fireEvent.click(screen.getByRole("button", { name: "Collapse all" }));

        expect(screen.queryByTestId("system-prompt-bill_summary_baltimore-maryland-united_states")).toBeNull();
        expect(screen.queryByTestId("system-prompt-unavailable-bill_categories")).toBeNull();
        expect(screen.getByRole("button", { name: "Expand all" })).toBeInTheDocument();
    });

    it("gives the reason instead of a prompt when one is not sent", () => {
        renderPage();

        openTrigger(/Bill categories/);

        expect(screen.getByTestId("system-prompt-unavailable-bill_categories")).toHaveTextContent(
            "No categorisation prompt is sent on this installation.",
        );
        expect(screen.queryByTestId("system-prompt-bill_categories")).toBeNull();
    });

    it("repeats each prompt's own model, including the counter-intuitive category mapping", () => {
        renderPage();

        const models = screen.getByTestId("system-prompts-models");
        expect(models).toHaveTextContent("claude-opus-5-5");
        expect(models).toHaveTextContent("claude-haiku-5-5");

        openTrigger(/Bill categories/);

        expect(screen.getByText(/Model: claude-opus-5-5 \(Summarization model\)/)).toBeInTheDocument();
    });

    it("links to the page that changes those models", () => {
        renderPage();

        expect(screen.getByRole("link", { name: /Change these models on LLM Settings/ })).toHaveAttribute(
            "href",
            "/admin/llm_settings",
        );
    });

    it("warns when the taxonomy is empty", () => {
        renderPage(0);

        expect(screen.getByTestId("system-prompts-empty-taxonomy")).toHaveTextContent("No active categories");
        expect(screen.queryByTestId("system-prompts-taxonomy")).toBeNull();
    });
});
