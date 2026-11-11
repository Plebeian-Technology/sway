// @lat: [[admin-llm-settings-stale-write-race#The fix: a per-field baseline and an expected guard]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const usePollMock = vi.fn<(interval: number, options: { only: string[] }) => void>();
const patch = vi.fn<(url: string, options: Record<string, unknown>) => void>();

let formData = {
    admin_setting: {
        summarization_model: "haiku",
        classification_model: "haiku",
        summarization_reasoning_effort: "",
        classification_reasoning_effort: "",
        summary_batch_enabled: false,
    },
};
let transform: (data: unknown) => unknown = (data) => data;

vi.mock("@inertiajs/react", () => ({
    router: {
        on: vi.fn<() => void>(),
        get: vi.fn<() => void>(),
        post: vi.fn<() => void>(),
        delete: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
    },
    Link: ({ href, children, ...props }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
    // Named `function usePoll` so the rules-of-hooks linter treats it as a hook.
    usePoll: function usePoll(interval: number, options: { only: string[] }) {
        usePollMock(interval, options);
    },
    usePage: () => ({ props: { flash: {}, errors: {} } }),
    useForm: () => ({
        data: formData,
        errors: {},
        processing: false,
        setData: (key: string, value: unknown) => {
            if (key === "admin_setting") {
                formData = { admin_setting: value as typeof formData.admin_setting };
                return;
            }
            const field = key.replace("admin_setting.", "");
            formData = {
                admin_setting: { ...formData.admin_setting, [field]: value } as typeof formData.admin_setting,
            };
        },
        transform: (fn: (data: unknown) => unknown) => {
            transform = fn;
        },
        patch,
    }),
}));

vi.mock("app/frontend/components/ui/combobox", () => ({
    Combobox: () => <div data-testid="mock-combobox" />,
}));

// Radix Select does not open under fireEvent in jsdom; the field is stubbed to
// a plain button per option so the examples are about this page's logic.
vi.mock("app/frontend/components/admin/llm-settings/ModelSelectField", () => ({
    default: ({ id, options, onChange }: { id: string; options: { id: string }[]; onChange: (v: string) => void }) => (
        <div>
            {options.map((option) => (
                <button
                    key={option.id}
                    type="button"
                    data-testid={`${id}-${option.id}`}
                    onClick={() => onChange(option.id)}
                >
                    {option.id}
                </button>
            ))}
        </div>
    ),
}));

import LlmSettings from "app/frontend/pages/admin/LlmSettings";

const MODELS: React.ComponentProps<typeof LlmSettings>["supported_models"] = [
    { id: "haiku", label: "Haiku", selectable: true },
    { id: "sonnet", label: "Sonnet", selectable: true },
    { id: "opus", label: "Opus", selectable: true },
];

const renderPage = (props: Partial<React.ComponentProps<typeof LlmSettings>> = {}) =>
    render(
        <LlmSettings
            supported_models={MODELS}
            current_summarization_model="haiku"
            current_classification_model="haiku"
            current_summary_batch_enabled={false}
            updated_by={null}
            updated_at="2026-07-28T00:00:00Z"
            {...props}
        />,
    );

const savedPayload = () => (transform({}) as { admin_setting: Record<string, unknown> }).admin_setting;

beforeEach(() => {
    formData = {
        admin_setting: {
            summarization_model: "haiku",
            classification_model: "haiku",
            summarization_reasoning_effort: "",
            classification_reasoning_effort: "",
            summary_batch_enabled: false,
        },
    };
    transform = (data) => data;
    usePollMock.mockClear();
    patch.mockClear();
});

afterEach(cleanup);

describe("admin/LlmSettings — self-refresh on a surface two admins share", () => {
    it("polls for every prop the other admin can move", () => {
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

    it("says nothing while the props still match what it rendered", () => {
        renderPage();

        expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();
    });

    it("tells the reader when a poll brings back another admin's change", () => {
        const { rerender } = renderPage();

        rerender(
            <LlmSettings
                supported_models={MODELS}
                current_summarization_model="opus"
                current_classification_model="haiku"
                current_summary_batch_enabled={false}
                updated_by={{ name: "Other Admin" }}
                updated_at="2026-07-28T00:05:00Z"
            />,
        );

        expect(screen.getByTestId("llm-settings-changed-elsewhere")).toBeInTheDocument();
    });

    // The load-bearing one. `expected` has to keep naming the value this page
    // was RENDERED with; if the poll moves it to the incoming value, the
    // server's per-field guard sees a match and the overwrite it exists to
    // refuse goes through.
    it("keeps staking the save on the value it rendered, not on the one the poll brought back", () => {
        const { rerender } = renderPage();

        fireEvent.click(screen.getByTestId("summarization-model-sonnet"));

        rerender(
            <LlmSettings
                supported_models={MODELS}
                current_summarization_model="opus"
                current_classification_model="haiku"
                current_summary_batch_enabled={false}
                updated_by={{ name: "Other Admin" }}
                updated_at="2026-07-28T00:05:00Z"
            />,
        );

        fireEvent.submit(screen.getByTestId("llm-settings-form"));

        expect(patch).toHaveBeenCalledTimes(1);
        expect(savedPayload()).toEqual({
            summarization_model: "sonnet",
            decision_model: undefined,
            extraction_model: undefined,
            expected: {
                summarization_model: "haiku",
                decision_model: "",
                extraction_model: "",
            },
        });
    });

    // And the admin is told that before they press it, rather than discovering
    // it from a refusal.
    it("warns that a save will be refused while a selection is open", () => {
        const { rerender } = renderPage();

        fireEvent.click(screen.getByTestId("summarization-model-sonnet"));
        rerender(
            <LlmSettings
                supported_models={MODELS}
                current_summarization_model="opus"
                current_classification_model="haiku"
                current_summary_batch_enabled={false}
                updated_by={{ name: "Other Admin" }}
                updated_at="2026-07-28T00:05:00Z"
            />,
        );

        expect(screen.getByTestId("llm-settings-changed-elsewhere")).toHaveTextContent("Saving now will be refused");
    });

    it("adopts the current values, and the new baseline with them, on request", () => {
        const { rerender } = renderPage();

        rerender(
            <LlmSettings
                supported_models={MODELS}
                current_summarization_model="opus"
                current_classification_model="haiku"
                current_summary_batch_enabled={false}
                updated_by={{ name: "Other Admin" }}
                updated_at="2026-07-28T00:05:00Z"
            />,
        );
        fireEvent.click(screen.getByTestId("btn-llm-settings-load-current"));

        expect(screen.queryByTestId("llm-settings-changed-elsewhere")).not.toBeInTheDocument();
        expect(formData.admin_setting.summarization_model).toBe("opus");
    });
});

const BATCH_SWITCH = { name: "Batch bill summarization" };

// @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
describe("admin/LlmSettings — the batch summarisation switch", () => {
    it("submits the flag, staked on the value the page was rendered with", () => {
        const { rerender } = renderPage();

        fireEvent.click(screen.getByRole("switch", BATCH_SWITCH));
        rerender(
            <LlmSettings
                supported_models={MODELS}
                current_summarization_model="haiku"
                current_classification_model="haiku"
                current_summary_batch_enabled={false}
                updated_by={null}
                updated_at="2026-07-28T00:00:00Z"
            />,
        );
        fireEvent.submit(screen.getByTestId("llm-settings-form"));

        expect(patch).toHaveBeenCalledTimes(1);
        expect(savedPayload()).toEqual({
            summary_batch_enabled: true,
            decision_model: undefined,
            extraction_model: undefined,
            expected: {
                summary_batch_enabled: false,
                decision_model: "",
                extraction_model: "",
            },
        });
    });

    it("warns when another admin moves the switch under it", () => {
        const { rerender } = renderPage();

        rerender(
            <LlmSettings
                supported_models={MODELS}
                current_summarization_model="haiku"
                current_classification_model="haiku"
                current_summary_batch_enabled
                updated_by={{ name: "Other Admin" }}
                updated_at="2026-07-28T00:05:00Z"
            />,
        );

        expect(screen.getByTestId("llm-settings-changed-elsewhere")).toBeInTheDocument();
    });
});
