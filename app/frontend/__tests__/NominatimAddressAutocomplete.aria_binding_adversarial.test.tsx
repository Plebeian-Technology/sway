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
    label: "Residential Address",
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

describe("NominatimAddressAutocomplete — ARIA Accessibility & Form Binding Adversarial Suite", () => {
    beforeEach(() => {
        useNominatimAddressAutocompleteMock.mockReset();
        mockHook();
    });

    afterEach(() => {
        cleanup();
    });

    describe("1. WAI-ARIA Combobox & Dropdown States (aria-expanded, aria-controls)", () => {
        it("strictly enforces aria-expanded='false' across all non-open hook statuses", () => {
            const nonOpenStatuses = ["IDLE", "LOADING", "ZERO_RESULTS", "ERROR", "UNKNOWN_STATUS"];
            const { rerender } = render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            for (const status of nonOpenStatuses) {
                mockHook({ status, suggestions: [createSuggestion("1", "Main", "Sub")] });
                rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
                expect(input.getAttribute("aria-expanded")).toBe("false");
                expect(input.getAttribute("aria-controls")).toBeNull();
                expect(screen.queryByRole("listbox")).toBeNull();
            }
        });

        it("strictly enforces aria-expanded='false' when status='OK' but suggestions array is empty", () => {
            mockHook({ status: "OK", suggestions: [] });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            expect(input.getAttribute("aria-expanded")).toBe("false");
            expect(input.getAttribute("aria-controls")).toBeNull();
            expect(screen.queryByRole("listbox")).toBeNull();
        });

        it("enforces aria-expanded='true' and links aria-controls to listbox ID when status='OK' with suggestions", () => {
            mockHook({
                status: "OK",
                suggestions: [createSuggestion("1", "100 Holliday St", "Baltimore, MD")],
            });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const listbox = screen.getByRole("listbox");

            expect(input.getAttribute("aria-expanded")).toBe("true");
            expect(input.getAttribute("aria-controls")).toBe(listbox.id);
            expect(listbox.getAttribute("role")).toBe("listbox");
            expect(listbox.getAttribute("aria-label")).toBe("Residential Address");
        });

        it("toggles aria-expanded and aria-controls dynamically through multi-phase search lifecycle", () => {
            const { rerender } = render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            expect(input.getAttribute("aria-expanded")).toBe("false");

            // Phase 1: In-flight search (LOADING, no suggestions yet)
            mockHook({ status: "LOADING", loading: true, suggestions: [] });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(input.getAttribute("aria-expanded")).toBe("false");

            // Phase 2: Results arrive (OK, 2 suggestions)
            mockHook({
                status: "OK",
                loading: false,
                suggestions: [
                    createSuggestion("1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("2", "200 E Pratt St", "Baltimore, MD"),
                ],
            });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const listbox = screen.getByRole("listbox");
            expect(input.getAttribute("aria-expanded")).toBe("true");
            expect(input.getAttribute("aria-controls")).toBe(listbox.id);

            // Phase 3: Selection made, suggestions cleared
            mockHook({ status: "IDLE", loading: false, suggestions: [] });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(input.getAttribute("aria-expanded")).toBe("false");
            expect(input.getAttribute("aria-controls")).toBeNull();
        });
    });

    describe("2. Active Descendant Linkage & Keyboard Focus (aria-activedescendant, aria-selected)", () => {
        it("omits aria-activedescendant initially when dropdown opens", () => {
            mockHook({
                status: "OK",
                suggestions: [
                    createSuggestion("1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("2", "200 E Pratt St", "Baltimore, MD"),
                ],
            });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            expect(input.getAttribute("aria-activedescendant")).toBeNull();
            expect(options[0].getAttribute("aria-selected")).toBe("false");
            expect(options[1].getAttribute("aria-selected")).toBe("false");
        });

        it("synchronizes aria-activedescendant with option id across forward and backward cyclic traversal", () => {
            const suggestions = [
                createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                createSuggestion("node-2", "200 E Pratt St", "Baltimore, MD"),
                createSuggestion("node-3", "300 Light St", "Baltimore, MD"),
            ];
            mockHook({ status: "OK", suggestions });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            // Step 1: ArrowDown -> option 0
            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBe(options[0].id);
            expect(options[0].getAttribute("aria-selected")).toBe("true");
            expect(options[1].getAttribute("aria-selected")).toBe("false");
            expect(options[2].getAttribute("aria-selected")).toBe("false");

            // Step 2: ArrowDown -> option 1
            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBe(options[1].id);
            expect(options[0].getAttribute("aria-selected")).toBe("false");
            expect(options[1].getAttribute("aria-selected")).toBe("true");
            expect(options[2].getAttribute("aria-selected")).toBe("false");

            // Step 3: ArrowDown -> option 2
            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBe(options[2].id);
            expect(options[2].getAttribute("aria-selected")).toBe("true");

            // Step 4: ArrowDown wrap -> option 0
            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBe(options[0].id);
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            // Step 5: ArrowUp backward wrap -> option 2
            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(input.getAttribute("aria-activedescendant")).toBe(options[2].id);
            expect(options[2].getAttribute("aria-selected")).toBe("true");
        });

        it("updates aria-activedescendant on mouseEnter and clears on typing", () => {
            mockHook({
                status: "OK",
                suggestions: [
                    createSuggestion("1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("2", "200 E Pratt St", "Baltimore, MD"),
                ],
            });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.mouseEnter(options[1]);
            expect(input.getAttribute("aria-activedescendant")).toBe(options[1].id);
            expect(options[1].getAttribute("aria-selected")).toBe("true");

            fireEvent.change(input, { target: { value: "New Search" } });
            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });
    });

    describe("3. In-Flight Search State (aria-busy, loading spinner, layout stability)", () => {
        it("strictly binds aria-busy to hook loading boolean", () => {
            const { rerender } = render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            expect(input.getAttribute("aria-busy")).toBe("false");
            expect(screen.queryByTestId("address-autocomplete-loading")).toBeNull();

            mockHook({ loading: true });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(input.getAttribute("aria-busy")).toBe("true");
            expect(input.className).toContain("pr-10");

            const spinner = screen.getByTestId("address-autocomplete-loading");
            expect(spinner.getAttribute("role")).toBe("status");
            expect(spinner.getAttribute("aria-label")).toBe("Loading address suggestions");

            mockHook({ loading: false });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(input.getAttribute("aria-busy")).toBe("false");
            expect(input.className).not.toContain("pr-10");
            expect(screen.queryByTestId("address-autocomplete-loading")).toBeNull();
        });
    });

    describe("4. Form Error Resilience & Assistive Tech (aria-invalid, aria-describedby, role='alert')", () => {
        it("binds aria-invalid and aria-describedby when field.name matches error key", () => {
            const form = buildForm({
                errors: { address: "Address must be within Maryland boundaries." },
            });
            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const alert = screen.getByRole("alert");

            expect(input.getAttribute("aria-invalid")).toBe("true");
            expect(input.getAttribute("aria-describedby")).toBe("address-error");
            expect(alert.id).toBe("address-error");
            expect(alert.textContent).toBe("Address must be within Maryland boundaries.");
        });

        it("displays fallback error when field.name has no error but another key does", () => {
            const form = buildForm({
                errors: { base: "Failed to connect to address verification service." },
            });
            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const alert = screen.getByRole("alert");

            expect(input.getAttribute("aria-invalid")).toBe("true");
            expect(input.getAttribute("aria-describedby")).toBe("address-error");
            expect(alert.textContent).toBe("Failed to connect to address verification service.");
        });

        it("prioritizes specific field.name error over other form errors", () => {
            const form = buildForm({
                errors: {
                    base: "Generic form failure",
                    address: "Exact street address is required.",
                },
            });
            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);
            const alert = screen.getByRole("alert");

            expect(alert.textContent).toBe("Exact street address is required.");
        });

        it("safely handles undefined, null, or empty form errors without crashing or setting aria-invalid", () => {
            const formEmpty = buildForm({ errors: {} });
            const { rerender } = render(<NominatimAddressAutocomplete form={formEmpty} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            expect(input.getAttribute("aria-invalid")).toBe("false");
            expect(input.getAttribute("aria-describedby")).toBeNull();
            expect(screen.queryByRole("alert")).toBeNull();

            const formNull = buildForm({ errors: undefined });
            rerender(<NominatimAddressAutocomplete form={formNull} field={REGISTRATION_FIELD} />);
            expect(input.getAttribute("aria-invalid")).toBe("false");
            expect(input.getAttribute("aria-describedby")).toBeNull();
            expect(screen.queryByRole("alert")).toBeNull();
        });

        it("ignores empty string error and does not render empty alert", () => {
            const formEmptyString = buildForm({ errors: { address: "" } });
            render(<NominatimAddressAutocomplete form={formEmptyString} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");

            expect(input.getAttribute("aria-invalid")).toBe("false");
            expect(input.getAttribute("aria-describedby")).toBeNull();
            expect(screen.queryByRole("alert")).toBeNull();
        });

        it("safely renders array-shaped error messages from backend validations", () => {
            const formArrayError = buildForm({
                errors: { address: ["Street line 1 is missing", "Postal code is invalid"] } as unknown as Record<
                    string,
                    string
                >,
            });
            render(<NominatimAddressAutocomplete form={formArrayError} field={REGISTRATION_FIELD} />);
            const input = screen.getByRole("combobox");
            const alert = screen.getByRole("alert");

            expect(input.getAttribute("aria-invalid")).toBe("true");
            expect(input.getAttribute("aria-describedby")).toBe("address-error");
            expect(alert.textContent).toContain("Street line 1 is missing");
        });
    });

    describe("5. OpenStreetMap Attribution Notice (role='presentation', aria-hidden='true')", () => {
        it("renders attribution with role='presentation' and aria-hidden='true' inside the listbox", () => {
            mockHook({
                status: "OK",
                suggestions: [
                    createSuggestion("1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("2", "200 E Pratt St", "Baltimore, MD"),
                ],
            });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const attribution = screen.getByTestId("osm-attribution");
            expect(attribution.getAttribute("role")).toBe("presentation");
            expect(attribution.getAttribute("aria-hidden")).toBe("true");
            expect(attribution.textContent).toContain("Search by Nominatim");
            expect(attribution.textContent).toContain("© OpenStreetMap contributors");
        });

        it("ensures assistive technology only enumerates real suggestion options, excluding attribution", () => {
            mockHook({
                status: "OK",
                suggestions: [
                    createSuggestion("1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("2", "200 E Pratt St", "Baltimore, MD"),
                ],
            });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const options = screen.getAllByRole("option");
            expect(options).toHaveLength(2);
            expect(options[0].textContent).toContain("100 Holliday St");
            expect(options[1].textContent).toContain("200 E Pratt St");
        });

        it("clicking the attribution notice does not trigger suggestion selection", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);

            mockHook({
                status: "OK",
                suggestions: [createSuggestion("1", "100 Holliday St", "Baltimore, MD")],
                handleSelect,
            });
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const attribution = screen.getByTestId("osm-attribution");
            fireEvent.click(attribution);

            expect(handleSelect).not.toHaveBeenCalled();
            expect(innerSelect).not.toHaveBeenCalled();
        });
    });

    describe("6. Form Data Binding & Input Attributes", () => {
        it("binds input name, id, required, and disabled attributes from field definition", () => {
            const customField: sway.IFormField<sway.IUser> = {
                name: "address",
                component: "text",
                type: "text",
                label: "Custom Address Label",
                isRequired: true,
                disabled: true,
            };
            render(<NominatimAddressAutocomplete form={buildForm()} field={customField} />);
            const input = screen.getByRole("combobox") as HTMLInputElement;
            const label = screen.getByText("Custom Address Label");

            expect(input.id).toBe("address");
            expect(input.name).toBe("address");
            expect(input.required).toBe(true);
            expect(input.disabled).toBe(true);
            expect(input.getAttribute("autoComplete")).toBe("off");
            expect(label.getAttribute("for")).toBe("address");
        });

        it("supports custom placeholder via props or field definition", () => {
            const fieldWithPlaceholder = {
                ...REGISTRATION_FIELD,
                placeholder: "Enter street, city, state...",
            };
            const { rerender } = render(
                <NominatimAddressAutocomplete form={buildForm()} field={fieldWithPlaceholder} />,
            );
            const input = screen.getByRole("combobox");
            expect(input.getAttribute("placeholder")).toBe("Enter street, city, state...");

            rerender(
                <NominatimAddressAutocomplete
                    form={buildForm()}
                    field={REGISTRATION_FIELD}
                    placeholder="Override placeholder via prop"
                />,
            );
            expect(input.getAttribute("placeholder")).toBe("Override placeholder via prop");
        });
    });
});
