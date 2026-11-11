import { render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));
vi.mock("@inertiajs/react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("@inertiajs/react")>();
    return { ...actual, usePage: () => ({ props: {} }) };
});
vi.mock("app/frontend/components/bill/BillSummaryMarkdown", () => ({
    __esModule: true,
    default: ({ summary }: { summary: string }) => <div data-testid="preview">{summary}</div>,
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorSummaryAudio", () => ({
    __esModule: true,
    default: () => <div data-testid="audio" />,
}));

import DateField from "app/frontend/components/admin/creator/fields/DateField";
import SelectField from "app/frontend/components/admin/creator/fields/SelectField";
import TextField from "app/frontend/components/admin/creator/fields/TextField";
import SummaryField from "app/frontend/components/admin/creator/fields/SummaryField";

const titleField = {
    name: "title" as const,
    component: "text" as const,
    type: "text" as const,
    label: "Title",
    isRequired: true,
};

const summaryField = {
    name: "summary" as const,
    component: "textarea" as const,
    type: "text" as const,
    label: "Summary",
    isRequired: false,
};

const introducedField = {
    name: "introduced_date_time_utc" as const,
    component: "date" as const,
    type: "date" as const,
    label: "Introduced",
    isRequired: true,
};

const chamberField = {
    name: "chamber" as const,
    component: "select" as const,
    type: "text" as const,
    label: "Chamber",
    isRequired: true,
    possibleValues: [
        { label: "Council", value: "council" },
        { label: "Senate", value: "senate" },
    ],
};

const provider = (data: Record<string, unknown>, errors: Record<string, unknown>) =>
    ({
        data,
        setData: vi.fn<(field: string, value: unknown) => void>(),
        errors,
        processing: false,
    }) as unknown as React.ContextType<typeof SwayFormContext>;

describe("Bill creator field errors are linked to their inputs", () => {
    it("points TextField's input at the error node and marks it invalid", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ title: "" }, { title: "Title is required" })}>
                <TextField swayField={titleField} />
            </SwayFormContext.Provider>,
        );

        const input = container.querySelector("#title") as HTMLInputElement;
        const alert = container.querySelector("[role='alert']") as HTMLElement;

        expect(alert).toHaveTextContent("Title is required");
        expect(alert.id).toBe("title-error");
        expect(input).toHaveAttribute("aria-describedby", "title-error");
        expect(input).toHaveAttribute("aria-invalid", "true");
    });

    it("leaves TextField's input undescribed and valid when there is no error", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ title: "A bill" }, {})}>
                <TextField swayField={titleField} />
            </SwayFormContext.Provider>,
        );

        const input = container.querySelector("#title") as HTMLInputElement;

        expect(container.querySelector("[role='alert']")).toBeNull();
        expect(input).not.toHaveAttribute("aria-describedby");
        expect(input).not.toHaveAttribute("aria-invalid");
    });

    it("points SummaryField's textarea at the error node and marks it invalid", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ summary: "" }, { summary: "Summary is required" })}>
                <SummaryField swayField={summaryField} />
            </SwayFormContext.Provider>,
        );

        const textarea = container.querySelector("#summary") as HTMLTextAreaElement;
        const alert = container.querySelector("[role='alert']") as HTMLElement;

        expect(alert).toHaveTextContent("Summary is required");
        expect(alert.id).toBe("summary-error");
        expect(textarea).toHaveAttribute("aria-describedby", "summary-error");
        expect(textarea).toHaveAttribute("aria-invalid", "true");
    });

    it("leaves SummaryField's textarea undescribed and valid when there is no error", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ summary: "Some text" }, {})}>
                <SummaryField swayField={summaryField} />
            </SwayFormContext.Provider>,
        );

        const textarea = container.querySelector("#summary") as HTMLTextAreaElement;

        expect(container.querySelector("[role='alert']")).toBeNull();
        expect(textarea).not.toHaveAttribute("aria-describedby");
        expect(textarea).not.toHaveAttribute("aria-invalid");
    });

    it("points DateField's input at the error node and marks it invalid", () => {
        const { container } = render(
            <SwayFormContext.Provider
                value={provider(
                    { introduced_date_time_utc: null },
                    { introduced_date_time_utc: "Introduced date is required" },
                )}
            >
                <DateField swayField={introducedField} />
            </SwayFormContext.Provider>,
        );

        const input = container.querySelector("#introduced_date_time_utc") as HTMLInputElement;
        const alert = container.querySelector("[role='alert']") as HTMLElement;

        expect(alert).toHaveTextContent("Introduced date is required");
        expect(alert.id).toBe("introduced_date_time_utc-error");
        expect(input).toHaveAttribute("aria-describedby", "introduced_date_time_utc-error");
        expect(input).toHaveAttribute("aria-invalid", "true");
    });

    it("leaves DateField's input undescribed and valid when there is no error", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ introduced_date_time_utc: "2026-01-02T00:00:00.000Z" }, {})}>
                <DateField swayField={introducedField} />
            </SwayFormContext.Provider>,
        );

        const input = container.querySelector("#introduced_date_time_utc") as HTMLInputElement;

        expect(container.querySelector("[role='alert']")).toBeNull();
        expect(input).not.toHaveAttribute("aria-describedby");
        expect(input).not.toHaveAttribute("aria-invalid");
    });

    it("points SelectField's trigger at the error node and marks it invalid", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ chamber: "" }, { chamber: "Chamber is required" })}>
                <SelectField swayField={chamberField} />
            </SwayFormContext.Provider>,
        );

        const trigger = container.querySelector("#chamber") as HTMLButtonElement;
        const alert = container.querySelector("[role='alert']") as HTMLElement;

        expect(alert).toHaveTextContent("Chamber is required");
        expect(alert.id).toBe("chamber-error");
        expect(trigger).toHaveAttribute("aria-describedby", "chamber-error");
        expect(trigger).toHaveAttribute("aria-invalid", "true");
    });

    it("leaves SelectField's trigger undescribed and valid when there is no error", () => {
        const { container } = render(
            <SwayFormContext.Provider value={provider({ chamber: "council" }, {})}>
                <SelectField swayField={chamberField} />
            </SwayFormContext.Provider>,
        );

        const trigger = container.querySelector("#chamber") as HTMLButtonElement;

        expect(container.querySelector("[role='alert']")).toBeNull();
        expect(trigger).not.toHaveAttribute("aria-describedby");
        expect(trigger).not.toHaveAttribute("aria-invalid");
    });
});
