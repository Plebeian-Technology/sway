// @lat: [[locale-extension#Nominatim geographic configuration]]
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { InertiaFormProps } from "@inertiajs/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import type {
    AddressSuggestion,
    UseNominatimAddressAutocomplete,
} from "app/frontend/hooks/useNominatimAddressAutocomplete";
import NominatimAddressAutocomplete from "app/frontend/components/user/NominatimAddressAutocomplete";

type TestFormData = Record<string, unknown>;
type TestForm = InertiaFormProps<TestFormData>;

type MockHookFn = (
    form: InertiaFormProps<TestFormData>,
    setLoading?: (loading: boolean) => void,
    locale?: sway.ISwayLocale | null,
) => UseNominatimAddressAutocomplete;

const useNominatimAddressAutocompleteMock = vi.fn<MockHookFn>();

vi.mock("app/frontend/hooks/useNominatimAddressAutocomplete", () => ({
    useNominatimAddressAutocomplete: (
        form: InertiaFormProps<TestFormData>,
        setLoading?: (loading: boolean) => void,
        locale?: sway.ISwayLocale | null,
    ) => useNominatimAddressAutocompleteMock(form, setLoading, locale),
}));

const REGISTRATION_FIELD: sway.IFormField<sway.IUser> = {
    name: "address",
    component: "text",
    type: "text",
    label: "Address",
    isRequired: true,
};

function buildForm(overrides: Partial<TestForm> = {}): TestForm {
    return {
        data: {},
        errors: {},
        hasErrors: false,
        processing: false,
        wasSuccessful: false,
        recentlySuccessful: false,
        setData: vi.fn<(key: string, value: unknown) => void>(),
        transform: vi.fn<() => unknown>(),
        reset: vi.fn<() => void>(),
        clearErrors: vi.fn<() => void>(),
        setError: vi.fn<() => void>(),
        post: vi.fn<() => void>(),
        put: vi.fn<() => void>(),
        patch: vi.fn<() => void>(),
        delete: vi.fn<() => void>(),
        get: vi.fn<() => void>(),
        progress: null,
        ...overrides,
    } as unknown as TestForm;
}

const createSuggestion = (place_id: string, main_text: string, secondary_text: string): AddressSuggestion => ({
    place_id,
    description: `${main_text}, ${secondary_text}`,
    structured_formatting: {
        main_text,
        secondary_text,
    },
});

interface IMockHookOptions {
    value?: string;
    status?: string;
    suggestions?: AddressSuggestion[];
    loading?: boolean;
    handleInput?: (e: React.ChangeEvent<HTMLInputElement>) => void;
    handleSelect?: (suggestion: AddressSuggestion) => () => void;
    clearSuggestions?: () => void;
}

function mockHook(overrides: IMockHookOptions = {}): UseNominatimAddressAutocomplete {
    const state: UseNominatimAddressAutocomplete = {
        value: "",
        status: "IDLE",
        suggestions: [],
        loading: false,
        handleInput: vi.fn<(e: React.ChangeEvent<HTMLInputElement>) => void>(),
        handleSelect: vi.fn<(suggestion: AddressSuggestion) => () => void>(() => vi.fn<() => void>()),
        clearSuggestions: vi.fn<() => void>(),
        ...overrides,
    };
    useNominatimAddressAutocompleteMock.mockReturnValue(state);
    return state;
}

describe("NominatimAddressAutocomplete — Adversarial Stress Harness", () => {
    beforeEach(() => {
        useNominatimAddressAutocompleteMock.mockReset();
        mockHook();
    });

    afterEach(() => {
        cleanup();
    });

    describe("Challenge Dimension 1: Rapid Keyboard Navigation & Modulo Wrapping Fuzzing", () => {
        it("fuzzes 50 consecutive ArrowDown keypresses wrapping seamlessly across 5 items", () => {
            const suggestions = [
                createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                createSuggestion("node-2", "200 E Pratt St", "Baltimore, MD"),
                createSuggestion("node-3", "300 Light St", "Baltimore, MD"),
                createSuggestion("node-4", "400 Charles St", "Baltimore, MD"),
                createSuggestion("node-5", "500 Cathedral St", "Baltimore, MD"),
            ];

            mockHook({
                value: "Street",
                status: "OK",
                suggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            for (let stroke = 0; stroke < 50; stroke++) {
                const expectedIndex = stroke % 5;
                fireEvent.keyDown(input, { key: "ArrowDown" });

                expect(options[expectedIndex].getAttribute("aria-selected")).toBe("true");
                expect(input.getAttribute("aria-activedescendant")).toBe(options[expectedIndex].id);

                for (let other = 0; other < 5; other++) {
                    const expectedSelection = other === expectedIndex ? "true" : "false";
                    expect(options[other].getAttribute("aria-selected")).toBe(expectedSelection);
                }
            }
        });

        it("fuzzes 50 consecutive ArrowUp keypresses wrapping backwards seamlessly across 5 items", () => {
            const suggestions = [
                createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                createSuggestion("node-2", "200 E Pratt St", "Baltimore, MD"),
                createSuggestion("node-3", "300 Light St", "Baltimore, MD"),
                createSuggestion("node-4", "400 Charles St", "Baltimore, MD"),
                createSuggestion("node-5", "500 Cathedral St", "Baltimore, MD"),
            ];

            mockHook({
                value: "Street",
                status: "OK",
                suggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            for (let stroke = 0; stroke < 50; stroke++) {
                const expectedIndex = (4 - (stroke % 5) + 5) % 5;
                fireEvent.keyDown(input, { key: "ArrowUp" });

                expect(options[expectedIndex].getAttribute("aria-selected")).toBe("true");
                expect(input.getAttribute("aria-activedescendant")).toBe(options[expectedIndex].id);
            }
        });

        it("fuzzes rapid alternating ArrowDown and ArrowUp keypresses without off-by-one errors", () => {
            const suggestions = [
                createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                createSuggestion("node-2", "200 E Pratt St", "Baltimore, MD"),
                createSuggestion("node-3", "300 Light St", "Baltimore, MD"),
            ];

            mockHook({
                value: "100",
                status: "OK",
                suggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            for (let cycle = 0; cycle < 15; cycle++) {
                fireEvent.keyDown(input, { key: "ArrowDown" });
                expect(options[1].getAttribute("aria-selected")).toBe("true");

                fireEvent.keyDown(input, { key: "ArrowUp" });
                expect(options[0].getAttribute("aria-selected")).toBe("true");
            }
        });

        it("handles single suggestion wrapping: ArrowDown and ArrowUp continuously select index 0", () => {
            const single = [createSuggestion("node-single", "Unique Address Way", "Baltimore, MD")];

            mockHook({
                value: "Unique",
                status: "OK",
                suggestions: single,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");
            expect(options).toHaveLength(1);

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");
        });

        it("survives dynamic suggestion list contraction when activeIndex exceeds new list length", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);

            const initialSuggestions = [
                createSuggestion("node-1", "100 A St", "Baltimore, MD"),
                createSuggestion("node-2", "200 B St", "Baltimore, MD"),
                createSuggestion("node-3", "300 C St", "Baltimore, MD"),
                createSuggestion("node-4", "400 D St", "Baltimore, MD"),
            ];

            mockHook({
                value: "St",
                status: "OK",
                suggestions: initialSuggestions,
                handleSelect,
            });

            const { rerender } = render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            fireEvent.keyDown(input, { key: "ArrowDown" });
            fireEvent.keyDown(input, { key: "ArrowDown" });
            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toContain("option-3");

            const contractedSuggestions = [
                createSuggestion("node-1", "100 A St", "Baltimore, MD"),
                createSuggestion("node-2", "200 B St", "Baltimore, MD"),
            ];

            mockHook({
                value: "St",
                status: "OK",
                suggestions: contractedSuggestions,
                handleSelect,
            });

            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            expect(() => {
                fireEvent.keyDown(input, { key: "Enter" });
            }).not.toThrow();

            expect(handleSelect).not.toHaveBeenCalled();
            expect(innerSelect).not.toHaveBeenCalled();

            fireEvent.keyDown(input, { key: "ArrowDown" });
            const currentOptions = screen.getAllByRole("option");
            expect(currentOptions[0].getAttribute("aria-selected")).toBe("true");
        });
    });

    describe("Challenge Dimension 2: Enter Key Selection vs Form Submission Mechanics", () => {
        it("allows native form submission on Enter when activeIndex is -1", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);

            mockHook({
                value: "Typed query without selection",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            const allowed = fireEvent.keyDown(input, { key: "Enter" });

            expect(allowed).toBe(true);
            expect(handleSelect).not.toHaveBeenCalled();
            expect(innerSelect).not.toHaveBeenCalled();
        });

        it("prevents form submission on Enter when activeIndex >= 0 and executes handleSelect", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);
            const target = createSuggestion("node-1", "100 Holliday St", "Baltimore, MD");

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [target],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });

            const allowed = fireEvent.keyDown(input, { key: "Enter" });

            expect(allowed).toBe(false);
            expect(handleSelect).toHaveBeenCalledWith(target);
            expect(innerSelect).toHaveBeenCalledTimes(1);

            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });

        it("double Enter test: second Enter after selection has activeIndex -1 and does not prevent default", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);
            const target = createSuggestion("node-1", "100 Holliday St", "Baltimore, MD");

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [target],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            const firstAllowed = fireEvent.keyDown(input, { key: "Enter" });
            expect(firstAllowed).toBe(false);
            expect(innerSelect).toHaveBeenCalledTimes(1);

            const secondAllowed = fireEvent.keyDown(input, { key: "Enter" });
            expect(secondAllowed).toBe(true);
            expect(innerSelect).toHaveBeenCalledTimes(1);
        });

        it("ignores Enter and allows default when dropdown is closed", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);

            mockHook({
                value: "Closed input",
                status: "IDLE",
                suggestions: [],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            const allowed = fireEvent.keyDown(input, { key: "Enter" });

            expect(allowed).toBe(true);
            expect(handleSelect).not.toHaveBeenCalled();
        });
    });

    describe("Challenge Dimension 3: Escape Key Dismissal & State Reset", () => {
        it("prevents default and invokes clearSuggestions when Escape is pressed while dropdown is open", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBeTruthy();

            const allowed = fireEvent.keyDown(input, { key: "Escape" });

            expect(allowed).toBe(false);
            expect(clearSuggestions).toHaveBeenCalledTimes(1);
            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });

        it("does not prevent default or call clearSuggestions when Escape is pressed while dropdown is closed", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "",
                status: "IDLE",
                suggestions: [],
                clearSuggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            const allowed = fireEvent.keyDown(input, { key: "Escape" });

            expect(allowed).toBe(true);
            expect(clearSuggestions).not.toHaveBeenCalled();
        });

        it("rapid repeated Escape presses execute cleanly without throwing", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            for (let i = 0; i < 5; i++) {
                expect(() => {
                    fireEvent.keyDown(input, { key: "Escape" });
                }).not.toThrow();
            }

            expect(clearSuggestions).toHaveBeenCalledTimes(5);
        });
    });

    describe("Challenge Dimension 4: Outside Click and Touch Event Dismissal", () => {
        it("dismisses suggestions via document touchstart on external elements", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            render(
                <div>
                    <div data-testid="mobile-backdrop">Mobile Outside Area</div>
                    <NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />
                </div>,
            );

            expect(screen.getByRole("listbox")).toBeTruthy();

            fireEvent.touchStart(screen.getByTestId("mobile-backdrop"));
            expect(clearSuggestions).toHaveBeenCalledTimes(1);
        });

        it("handles mobile touch-then-mouse double events gracefully", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            render(
                <div>
                    <div data-testid="mobile-backdrop">Mobile Outside Area</div>
                    <NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />
                </div>,
            );

            const backdrop = screen.getByTestId("mobile-backdrop");

            fireEvent.touchStart(backdrop);
            fireEvent.mouseDown(backdrop);

            expect(clearSuggestions).toHaveBeenCalledTimes(2);
        });

        it("preserves dropdown when clicking container elements", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                loading: true,
                clearSuggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const label = screen.getByText("Address");
            const spinner = screen.getByTestId("address-autocomplete-loading");

            fireEvent.mouseDown(input);
            fireEvent.mouseDown(label);
            fireEvent.mouseDown(spinner);

            expect(clearSuggestions).not.toHaveBeenCalled();
            expect(screen.getByRole("listbox")).toBeTruthy();
        });

        it("cleans up document listeners when component unmounts", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            const { unmount } = render(
                <div>
                    <div data-testid="outside">Outside</div>
                    <NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />
                </div>,
            );

            unmount();

            const outsideNode = document.createElement("div");
            document.body.appendChild(outsideNode);
            fireEvent.mouseDown(outsideNode);
            fireEvent.touchStart(outsideNode);

            expect(clearSuggestions).not.toHaveBeenCalled();
            outsideNode.remove();
        });
    });

    describe("Challenge Dimension 5: Mouse Hover & Keyboard Interleaving", () => {
        it("synchronizes mouse hover highlighting with keyboard Arrow navigation", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("node-2", "200 E Pratt St", "Baltimore, MD"),
                    createSuggestion("node-3", "300 Light St", "Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.mouseEnter(options[2]);
            expect(options[2].getAttribute("aria-selected")).toBe("true");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[2].id);

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[0].id);

            fireEvent.mouseEnter(options[1]);
            expect(options[1].getAttribute("aria-selected")).toBe("true");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[1].id);

            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[0].id);
        });

        it("selects hovered option on Enter", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);
            const target = createSuggestion("node-2", "200 E Pratt St", "Baltimore, MD");

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"), target],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.mouseEnter(options[1]);
            fireEvent.keyDown(input, { key: "Enter" });

            expect(handleSelect).toHaveBeenCalledWith(target);
            expect(innerSelect).toHaveBeenCalledTimes(1);
        });
    });

    describe("Challenge Dimension 6: Typing Interruption & State Reset", () => {
        it("resets activeIndex and activedescendant immediately upon typing change", () => {
            const handleInput = vi.fn<(e: React.ChangeEvent<HTMLInputElement>) => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                handleInput,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBeTruthy();

            fireEvent.change(input, { target: { value: "100 Hol" } });

            expect(input.getAttribute("aria-activedescendant")).toBeNull();
            expect(handleInput).toHaveBeenCalledTimes(1);
        });

        it("handles empty typing value cleanly", () => {
            const handleInput = vi.fn<(e: React.ChangeEvent<HTMLInputElement>) => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                handleInput,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            fireEvent.change(input, { target: { value: "" } });

            expect(input.getAttribute("aria-activedescendant")).toBeNull();
            expect(handleInput).toHaveBeenCalledTimes(1);
        });
    });

    describe("Challenge Dimension 7: Error State Edge Cases & Resiliency", () => {
        it("prioritizes exact field.name error over fallback error", () => {
            const form = buildForm({
                errors: {
                    otherField: "Other field error",
                    address: "Exact address error",
                },
            });

            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);
            const alert = screen.getByRole("alert");
            expect(alert.textContent).toBe("Exact address error");
        });

        it("gracefully displays fallback error when exact field.name is absent", () => {
            const form = buildForm({
                errors: {
                    base: "Base validation error occurred",
                },
            });

            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);
            const alert = screen.getByRole("alert");
            expect(alert.textContent).toBe("Base validation error occurred");
        });

        it("does not render alert when errors object is empty", () => {
            const form = buildForm({
                errors: {},
            });

            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);
            expect(screen.queryByRole("alert")).toBeNull();
        });
    });
});
