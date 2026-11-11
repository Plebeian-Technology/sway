import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { SWAY_STORAGE } from "app/frontend/sway_utils";

const pagePropsRef: { current: Record<string, unknown> } = { current: {} };

// A stateful useForm stand-in: a stateless mock returning `data: initial` would hide the
// C23-01 defect, since useForm reads its argument at mount only, never again.
vi.mock("@inertiajs/react", async () => {
    const { useCallback, useState } = await import("react");

    return {
        router: {
            on: vi.fn<() => () => void>(() => () => {}),
            visit: vi.fn<() => void>(),
            get: vi.fn<() => void>(),
        },
        usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: pagePropsRef.current })),
        useForm: (initial: Record<string, unknown>) => {
            const [data, setDataState] = useState<Record<string, unknown>>(initial);
            const setData = useCallback(
                (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value })),
                [],
            );
            return {
                data,
                setData,
                processing: false,
                errors: {},
                reset: vi.fn<() => void>(),
                transform: vi.fn<(data: Record<string, unknown>) => void>(),
            };
        },
    };
});

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ id: 7, name: "test" }, vi.fn<(locale: { id: number; name: string }) => void>()],
}));

vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return { ...actual, notify: vi.fn<(options: Record<string, unknown>) => void>() };
});

// The submit path, the header and the field components are not what this file is
// about. Only the auto-saved draft is.
vi.mock("app/frontend/components/admin/creator/hooks/useBillFormSubmit", () => ({
    useBillFormSubmit: () => ({ onSubmit: vi.fn<() => void>() }),
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorFormHeader", () => ({ default: () => <div /> }));
vi.mock("app/frontend/components/admin/creator/fields/DateField", () => ({ default: () => <div /> }));
// A button stands in for the real dropdown; its click, not onBlur, marks a choice — the
// trigger's blur fires when the dropdown opens, which is the C24-04 defect a blur-based mock
// would hide.
vi.mock("app/frontend/components/admin/creator/fields/SelectField", () => ({
    default: ({ swayField, onStored }: { swayField: { name: string }; onStored?: (name: string) => void }) => (
        <button
            type="button"
            data-testid={`field-${swayField.name}`}
            name={swayField.name}
            aria-label={swayField.name}
            onClick={() => onStored?.(swayField.name)}
        />
    ),
}));
// The only non-stub field mock: it renders and updates the summary in form data.
vi.mock("app/frontend/components/admin/creator/fields/SummaryField", async () => {
    const { useSwayFormContext } = await import("app/frontend/components/admin/creator/context/useSwayFormContext");

    const MockSummaryField: React.FC<{
        onBlur: (e: React.FocusEvent<HTMLTextAreaElement>) => void;
    }> = ({ onBlur }) => {
        const { data, setData } = useSwayFormContext<{ summary?: string }>();
        return (
            <textarea
                data-testid="field-summary"
                name="summary"
                value={data.summary ?? ""}
                onBlur={onBlur}
                onChange={(e) => {
                    setData("summary" as never, e.target.value as never);
                }}
            />
        );
    };

    return { default: MockSummaryField };
});
vi.mock("app/frontend/components/admin/creator/fields/TextField", async () => {
    const { useSwayFormContext } = await import("app/frontend/components/admin/creator/context/useSwayFormContext");

    const MockTextField: React.FC<{
        swayField: { name: string };
        onBlur: (e: React.FocusEvent<HTMLInputElement>) => void;
    }> = ({ swayField, onBlur }) => {
        const { setData } = useSwayFormContext();
        return (
            <>
                <input data-testid={`field-${swayField.name}`} name={swayField.name} onBlur={onBlur} />
                {swayField.name === "title" && (
                    <button
                        type="button"
                        data-testid="set-summary-externally"
                        aria-label="Set summary externally"
                        onClick={() => setData("summary" as never, "Programmatic summary update" as never)}
                    />
                )}
            </>
        );
    };

    return {
        default: MockTextField,
    };
});

import BillCreatorBillForm from "app/frontend/components/admin/creator/BillCreatorBillForm";

const BILL_KEY = SWAY_STORAGE.Local.BillCreator.Bill;

// bills.summary has two editors (this form and Summary tab's Save). The draft must record
// which published summary it was written against, or Save Bill republishes stale text. (C22-04)
describe("BillCreatorBillForm — what the auto-saved draft records", () => {
    beforeEach(() => {
        localStorage.clear();
        pagePropsRef.current = {
            bill: { id: 42, title: "Bill Forty-Two", summary: "The published summary." },
            legislators: [],
            organizations: [],
        };
    });

    const storeDraft = () => {
        render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        fireEvent.blur(screen.getByTestId("field-title"));
        return JSON.parse(localStorage.getItem(BILL_KEY) ?? "{}");
    };

    it("stamps the draft with the published summary it was written against", () => {
        expect(storeDraft().summary_at_draft_time).toBe("The published summary.");
    });

    // The three dropdowns never reached browser storage, so a chosen sponsor, chamber or
    // status really was lost on a tab switch. (C23-05, C24-04)
    it("auto-saves a dropdown choice the same way it auto-saves a typed field", () => {
        render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        expect(localStorage.getItem(BILL_KEY)).toBeNull();

        fireEvent.click(screen.getByTestId("field-status"));

        expect(localStorage.getItem(BILL_KEY)).not.toBeNull();
    });

    // Stamps off the SERVER's props, not the form's initial values — those may themselves be
    // a restored draft, and a draft cannot be its own provenance.
    it("stamps the server's summary even when the form starts from a restored draft", () => {
        localStorage.setItem(
            BILL_KEY,
            JSON.stringify({
                id: 42,
                title: "Bill Forty-Two",
                summary: "An older draft summary.",
                summary_at_draft_time: "The published summary.",
            }),
        );

        expect(storeDraft().summary_at_draft_time).toBe("The published summary.");
    });
});

// useForm reads its initial values once at mount, so props.bill can later be replaced
// under a form that never rebuilds — e.g. RunConflictBanner's Cancel. (C23-01, C23-02)
describe("BillCreatorBillForm — when bills.summary moves under the open form", () => {
    const PUBLISHED = "The published summary.";
    const CORRECTED = "A corrected summary.";
    const TYPED = "My unsaved paragraph.";

    const setPublishedSummary = (summary: string) => {
        pagePropsRef.current = {
            ...pagePropsRef.current,
            bill: { id: 42, title: "Bill Forty-Two", summary },
        };
    };

    beforeEach(() => {
        localStorage.clear();
        pagePropsRef.current = { legislators: [], organizations: [] };
        setPublishedSummary(PUBLISHED);
    });

    const storedDraft = () => JSON.parse(localStorage.getItem(BILL_KEY) ?? "{}");

    it("shows and saves the server's new summary when the operator has not touched the box", () => {
        const { rerender } = render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        expect(screen.getByTestId("field-summary")).toHaveValue(PUBLISHED);

        setPublishedSummary(CORRECTED);
        rerender(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);

        expect(screen.getByTestId("field-summary")).toHaveValue(CORRECTED);
        fireEvent.blur(screen.getByTestId("field-title"));
        expect(storedDraft().summary).toBe(CORRECTED);
    });

    it("keeps a half-typed summary when the server's summary moves", () => {
        const { rerender } = render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        fireEvent.change(screen.getByTestId("field-summary"), { target: { value: TYPED } });

        setPublishedSummary(CORRECTED);
        rerender(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);

        expect(screen.getByTestId("field-summary")).toHaveValue(TYPED);
    });

    it("stamps the draft with the summary the text was written against, not one that arrived later", () => {
        const { rerender } = render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        fireEvent.change(screen.getByTestId("field-summary"), { target: { value: TYPED } });

        setPublishedSummary(CORRECTED);
        rerender(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        fireEvent.blur(screen.getByTestId("field-title"));

        expect(storedDraft().summary).toBe(TYPED);
        expect(storedDraft().summary_at_draft_time).toBe(PUBLISHED);
    });

    it("moves the stamp when the server catches up with the box, so a restore keeps the draft", () => {
        const { rerender } = render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        fireEvent.change(screen.getByTestId("field-summary"), { target: { value: TYPED } });

        // This form's own Save Bill landing: props come back holding exactly
        // what the box holds. Nothing was superseded, so the draft must not be
        // dropped on the next restore.
        setPublishedSummary(TYPED);
        rerender(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);
        fireEvent.blur(screen.getByTestId("field-title"));

        expect(storedDraft().summary_at_draft_time).toBe(TYPED);
    });

    it("autosaves a summary written through form setData without a textarea change", () => {
        render(<BillCreatorBillForm setCreatorDirty={vi.fn<(...args: unknown[]) => void>()} />);

        fireEvent.click(screen.getByTestId("set-summary-externally"));
        fireEvent.blur(screen.getByTestId("field-title"));

        expect(storedDraft().summary).toBe("Programmatic summary update");
    });
});
