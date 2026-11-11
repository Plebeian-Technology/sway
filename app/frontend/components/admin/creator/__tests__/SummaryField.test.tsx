// @lat: [[bill-creator-form-state#The summary field reads current form data]]

import { fireEvent, render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));
vi.mock("app/frontend/components/bill/BillSummaryMarkdown", () => ({
    __esModule: true,
    default: ({ summary }: { summary: string }) => <div data-testid="preview">{summary}</div>,
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorSummaryAudio", () => ({
    __esModule: true,
    default: () => <div data-testid="audio" />,
}));

import SummaryField from "app/frontend/components/admin/creator/fields/SummaryField";

const summaryField = {
    name: "summary" as const,
    component: "textarea" as const,
    type: "text" as const,
    label: "Summary",
    isRequired: false,
};

const provider = (summary: string, setData: ReturnType<typeof vi.fn>) =>
    ({
        data: { summary },
        setData,
        errors: {},
    }) as unknown as React.ContextType<typeof SwayFormContext>;

describe("SummaryField — single source of truth", () => {
    it("writes a changed summary to form data", () => {
        const setData = vi.fn<(field: string, value: unknown) => void>();
        const { container } = render(
            <SwayFormContext.Provider value={provider("initial", setData)}>
                <SummaryField swayField={summaryField} />
            </SwayFormContext.Provider>,
        );

        const textarea = container.querySelector("#summary") as HTMLTextAreaElement;
        expect(textarea.value).toBe("initial");

        fireEvent.change(textarea, { target: { value: "updated" } });

        expect(setData).toHaveBeenCalledWith("summary", "updated");
    });

    it("reflects an external data.summary change in the textarea (no stale mirror)", () => {
        const setData = vi.fn<(field: string, value: unknown) => void>();
        const { container, rerender } = render(
            <SwayFormContext.Provider value={provider("v1", setData)}>
                <SummaryField swayField={summaryField} />
            </SwayFormContext.Provider>,
        );
        expect((container.querySelector("#summary") as HTMLTextAreaElement).value).toBe("v1");

        // External write (LLM paste / form.reset) updates the shared form data.
        rerender(
            <SwayFormContext.Provider value={provider("v2-external", setData)}>
                <SummaryField swayField={summaryField} />
            </SwayFormContext.Provider>,
        );

        expect((container.querySelector("#summary") as HTMLTextAreaElement).value).toBe("v2-external");
    });

    it("keeps a disabled summary in form data while the browser omits it from FormData", () => {
        const setData = vi.fn<(field: string, value: unknown) => void>();
        const { container } = render(
            <form>
                <SwayFormContext.Provider value={provider("current form value", setData)}>
                    <SummaryField swayField={{ ...summaryField, disabled: true }} />
                </SwayFormContext.Provider>
            </form>,
        );

        const form = container.querySelector("form") as HTMLFormElement;
        const textarea = container.querySelector("#summary") as HTMLTextAreaElement;

        expect(textarea).toBeDisabled();
        expect(textarea).toHaveValue("current form value");
        expect(new FormData(form).has("summary")).toBe(false);
    });
});
