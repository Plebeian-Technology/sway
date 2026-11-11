import { useState, type ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent } from "@testing-library/react";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";
import { renderV2, resetInertiaStubs, setPageProps, type InertiaStubs } from "app/frontend/__tests__/test-utils";

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} as Record<string, unknown> })),
    router: {
        visit: vi.fn<(url: string) => void>(),
        post: vi.fn<(url: string, data?: unknown) => void>(),
        put: vi.fn<(url: string, data?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown) => void>(),
        delete: vi.fn<(url: string) => void>(),
        get: vi.fn<(url: string) => void>(),
        reload: vi.fn<(opts?: Record<string, unknown>) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return { ...actual, usePage: inertia.usePage, router: inertia.router };
});

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [{ name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));

// Swap the Radix Select for plain HTML so the tests can read the options
// straight off the page. The component under test still builds the option
// labels itself; only the widget that draws them is replaced.
vi.mock("app/frontend/components/ui/select", () => {
    const Passthrough = ({ children }: { children?: ReactNode }) => <>{children}</>;
    return {
        // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
        Select: ({
            children,
            onValueChange,
            onOpenChange,
        }: {
            children: ReactNode;
            onValueChange?: (value: string) => void;
            onOpenChange?: (open: boolean) => void;
        }) => (
            <div data-testid="select-shim">
                <button type="button" data-testid="select-open" onClick={() => onOpenChange?.(true)}>
                    open
                </button>
                <button type="button" data-testid="select-close" onClick={() => onOpenChange?.(false)}>
                    close
                </button>
                <button type="button" data-testid="select-choose" onClick={() => onValueChange?.("passed")}>
                    choose
                </button>
                {children}
            </div>
        ),
        // A real BUTTON, because that is what the shadcn Select draws and
        // because the props it forwards are the subject of one test below: a
        // Select choice can only reach the browser draft if `name` and `onBlur`
        // land on the trigger. (C23-05)
        SelectTrigger: ({ children, ...props }: { children?: ReactNode } & React.ComponentProps<"button">) => (
            <button type="button" {...props}>
                {children}
            </button>
        ),
        SelectValue: Passthrough,
        SelectContent: ({ children }: { children: ReactNode }) => <div data-testid="select-options">{children}</div>,
        SelectItem: ({ value, children }: { value: string; children: ReactNode }) => (
            <div data-testid="select-item" data-value={value}>
                {children}
            </div>
        ),
    };
});

import SelectField from "app/frontend/components/admin/creator/fields/SelectField";

const legislatorField = {
    name: "legislator_id" as const,
    component: "select" as const,
    type: "text" as const,
    label: "Legislator Sponsor",
    isRequired: true,
};

const renderWithFormContext = (ui: React.ReactElement, contextValue: Partial<Record<string, unknown>> = {}) => {
    const formValue = {
        data: {},
        setData: vi.fn<(key: string, value: unknown) => void>(),
        errors: {},
        processing: false,
        progress: null,
        wasSuccessful: false,
        recentlySuccessful: false,
        isDirty: false,
        ...contextValue,
        // InertiaFormProps carries more than this, but SelectField only reads
        // data, setData, and errors. The cast keeps TypeScript happy.
    } as unknown as React.ContextType<typeof SwayFormContext>;

    return renderV2(<SwayFormContext.Provider value={formValue}>{ui}</SwayFormContext.Provider>);
};

beforeEach(() => {
    resetInertiaStubs(inertia);
});

describe("SelectField — legislator_id branch", () => {
    it("formats options as 'Last, First (REGION - NUMBER)' sorted by label", () => {
        setPageProps(inertia, {
            legislators: [
                {
                    id: 10,
                    first_name: "zeke",
                    last_name: "Cohen",
                    party: "D",
                    district: { region_code: "BAL", number: 1 },
                },
                {
                    id: 20,
                    first_name: "sharon",
                    last_name: "Middleton",
                    party: "D",
                    district: { region_code: "BAL", number: 6 },
                },
                {
                    id: 30,
                    first_name: "ryan",
                    last_name: "Dorsey",
                    party: "D",
                    district: { region_code: "BAL", number: 3 },
                },
            ],
        });

        const { getAllByTestId } = renderWithFormContext(<SelectField swayField={legislatorField} />);

        const labels = getAllByTestId("select-item").map((el) => el.textContent);
        expect(labels).toEqual(["Cohen, Zeke (BAL - 1)", "Dorsey, Ryan (BAL - 3)", "Middleton, Sharon (BAL - 6)"]);
    });

    it("uses each legislator's id as the option value", () => {
        setPageProps(inertia, {
            legislators: [
                {
                    id: 99,
                    first_name: "Jane",
                    last_name: "Doe",
                    party: "I",
                    district: { region_code: "MD", number: 12 },
                },
            ],
        });

        const { getByTestId } = renderWithFormContext(<SelectField swayField={legislatorField} />);

        expect(getByTestId("select-item")).toHaveAttribute("data-value", "99");
    });

    it("renders zero options when no legislators are provided", () => {
        setPageProps(inertia, { legislators: [] });

        const { queryAllByTestId } = renderWithFormContext(<SelectField swayField={legislatorField} />);

        expect(queryAllByTestId("select-item")).toHaveLength(0);
    });
});

describe("SelectField — possibleValues passthrough", () => {
    it("renders the options listed in swayField.possibleValues", () => {
        setPageProps(inertia, {});
        const chamberField = {
            name: "chamber" as const,
            component: "select" as const,
            type: "text" as const,
            label: "Chamber",
            isRequired: true,
            possibleValues: [
                { label: "House", value: "house" },
                { label: "Senate", value: "senate" },
            ],
        };

        const { getAllByTestId } = renderWithFormContext(<SelectField swayField={chamberField} />);

        const items = getAllByTestId("select-item");
        expect(items.map((el) => el.textContent)).toEqual(["House", "Senate"]);
        expect(items.map((el) => el.getAttribute("data-value"))).toEqual(["house", "senate"]);
    });
});

describe("SelectField — explicit options prop", () => {
    it("prefers the options prop over page props or possibleValues", () => {
        setPageProps(inertia, {
            legislators: [
                {
                    id: 1,
                    first_name: "A",
                    last_name: "B",
                    party: "D",
                    district: { region_code: "X", number: 1 },
                },
            ],
        });

        const { getAllByTestId } = renderWithFormContext(
            <SelectField
                swayField={legislatorField}
                options={[
                    { label: "Explicit One", value: "1" },
                    { label: "Explicit Two", value: "2" },
                ]}
            />,
        );

        const items = getAllByTestId("select-item");
        expect(items.map((el) => el.textContent)).toEqual(["Explicit One", "Explicit Two"]);
    });
});

// @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
describe("SelectField — reaching the auto-saved draft", () => {
    const statusField = {
        name: "status" as const,
        component: "select" as const,
        type: "text" as const,
        label: "Status",
        isRequired: true,
        possibleValues: [
            { label: "Committee", value: "committee" },
            { label: "Passed", value: "passed" },
        ],
    };

    it("stores the field when the operator chooses a value", () => {
        const onStored = vi.fn<(name: string, value?: unknown) => void>();
        const { getByTestId } = renderWithFormContext(<SelectField swayField={statusField} onStored={onStored} />);

        fireEvent.click(getByTestId("select-open"));
        fireEvent.click(getByTestId("select-choose"));

        // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
        expect(onStored).toHaveBeenCalledTimes(1);
        expect(onStored).toHaveBeenCalledWith("status", { status: "passed" });
    });

    it("stores nothing when the dropdown only opens", () => {
        const onStored = vi.fn<(name: string, value?: unknown) => void>();
        const { getByTestId, container } = renderWithFormContext(
            <SelectField swayField={statusField} onStored={onStored} />,
        );

        // Radix's order: the open is announced, then focus leaves the trigger.
        fireEvent.click(getByTestId("select-open"));
        fireEvent.blur(container.querySelector("#status") as Element);

        expect(onStored).not.toHaveBeenCalled();
    });

    it("stores nothing when the dropdown is opened and closed without a choice", () => {
        const onStored = vi.fn<(name: string, value?: unknown) => void>();
        const { getByTestId, container } = renderWithFormContext(
            <SelectField swayField={statusField} onStored={onStored} />,
        );

        fireEvent.click(getByTestId("select-open"));
        fireEvent.blur(container.querySelector("#status") as Element);
        fireEvent.click(getByTestId("select-close"));

        expect(onStored).not.toHaveBeenCalled();
    });

    // The other direction. Tabbing across a dropdown the operator never opened
    // still writes the draft, the same as the ten text and date fields beside
    // it — otherwise a field that had simply stopped storing would pass every
    // example above.
    it("still stores on an ordinary blur, with the dropdown never opened", () => {
        const onStored = vi.fn<(name: string, value?: unknown) => void>();
        const { container } = renderWithFormContext(<SelectField swayField={statusField} onStored={onStored} />);

        fireEvent.blur(container.querySelector("#status") as Element);

        expect(onStored).toHaveBeenCalledWith("status");
    });

    // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
    describe("what the draft actually holds after a choice", () => {
        const DRAFT_KEY = "select-field-draft";

        const Harness: React.FC = () => {
            const [data, setData] = useState<Record<string, unknown>>({ status: "committee" });
            const formValue = {
                data,
                setData: (name: string, value: unknown) => setData((prev) => ({ ...prev, [name]: value })),
                errors: {},
            } as unknown as React.ContextType<typeof SwayFormContext>;

            // The one thing BillCreatorBillForm does: build the payload from the
            // form data this render closed over, then merge whatever the field
            // hands back.
            const onStored = (_name: string, override?: Record<string, unknown>) =>
                localStorage.setItem(DRAFT_KEY, JSON.stringify({ ...data, ...override }));

            return (
                <SwayFormContext.Provider value={formValue}>
                    <SelectField swayField={statusField} onStored={onStored} />
                </SwayFormContext.Provider>
            );
        };

        it("writes the value the operator just chose, not the one it replaced", () => {
            localStorage.removeItem(DRAFT_KEY);
            const { getByTestId } = renderV2(<Harness />);

            fireEvent.click(getByTestId("select-open"));
            fireEvent.click(getByTestId("select-choose"));

            expect(JSON.parse(localStorage.getItem(DRAFT_KEY) as string).status).toBe("passed");
        });
    });
});
