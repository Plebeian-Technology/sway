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

const BALTIMORE_LOCALE: sway.ISwayLocale = {
    id: 1,
    name: "baltimore-maryland-united_states",
    city: "baltimore",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/baltimore-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2024-12-05",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-76.7114,39.3720,-76.5297,39.1972",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
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

describe("NominatimAddressAutocomplete", () => {
    beforeEach(() => {
        useNominatimAddressAutocompleteMock.mockReset();
        mockHook();
    });

    afterEach(() => {
        cleanup();
    });

    describe("1. Rendering & Basic Props", () => {
        it("renders the labeled input without Google Maps SDK loader or skeleton", () => {
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            expect(screen.getByLabelText("Address")).toBeTruthy();
            expect(screen.queryByTestId("address-autocomplete-skeleton")).toBeNull();
        });

        it("renders input with default placeholder '1 W Elm St' when not specified in field", () => {
            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            expect(input.getAttribute("placeholder")).toBe("1 W Elm St");
        });

        it("renders custom placeholder when specified on field configuration", () => {
            render(
                <NominatimAddressAutocomplete
                    form={buildForm()}
                    field={REGISTRATION_FIELD}
                    placeholder="Search Baltimore street address..."
                />,
            );

            const input = screen.getByRole("combobox");
            expect(input.getAttribute("placeholder")).toBe("Search Baltimore street address...");
        });

        it("renders initial value supplied by the autocomplete hook", () => {
            mockHook({ value: "100 Holliday St" });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox") as HTMLInputElement;
            expect(input.value).toBe("100 Holliday St");
        });

        it("forwards typing events to the hook's handleInput", () => {
            const handleInput = vi.fn<(e: React.ChangeEvent<HTMLInputElement>) => void>();
            mockHook({ handleInput });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            fireEvent.change(screen.getByRole("combobox"), { target: { value: "100 Hol" } });

            expect(handleInput).toHaveBeenCalledTimes(1);
        });

        it("passes form, setLoading, and locale props directly to useNominatimAddressAutocomplete hook", () => {
            const form = buildForm();
            const setLoading = vi.fn<(loading: boolean) => void>();

            render(
                <NominatimAddressAutocomplete
                    form={form}
                    field={REGISTRATION_FIELD}
                    setLoading={setLoading}
                    locale={BALTIMORE_LOCALE}
                />,
            );

            expect(useNominatimAddressAutocompleteMock).toHaveBeenCalledWith(form, setLoading, BALTIMORE_LOCALE);
        });

        it("respects field.isRequired and field.disabled attributes", () => {
            const disabledField: sway.IFormField<sway.IUser> = {
                ...REGISTRATION_FIELD,
                isRequired: true,
                disabled: true,
            };

            render(<NominatimAddressAutocomplete form={buildForm()} field={disabledField} />);

            const input = screen.getByRole("combobox") as HTMLInputElement;
            expect(input.required).toBe(true);
            expect(input.disabled).toBe(true);
        });
    });

    describe("2. Suggestions List & Presentation", () => {
        it("renders suggestions listbox when hook reports status='OK' and suggestions are non-empty", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Downtown, Baltimore, MD"),
                    createSuggestion("node-2", "100 E Pratt St", "Inner Harbor, Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            expect(screen.getByRole("listbox")).toBeTruthy();
            const options = screen.getAllByRole("option");
            expect(options).toHaveLength(2);
        });

        it("renders main and secondary text in suggestion options", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Downtown, Baltimore, MD")],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            expect(screen.getByText("100 Holliday St")).toBeTruthy();
            expect(screen.getByText("Downtown, Baltimore, MD")).toBeTruthy();
        });

        it("does not render listbox when suggestions are empty", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            expect(screen.queryByRole("listbox")).toBeNull();
        });

        it("does not render listbox when status is 'IDLE', 'ZERO_RESULTS', or 'ERROR'", () => {
            const { rerender } = render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(screen.queryByRole("listbox")).toBeNull();

            mockHook({ status: "ZERO_RESULTS", suggestions: [] });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(screen.queryByRole("listbox")).toBeNull();

            mockHook({ status: "ERROR", suggestions: [] });
            rerender(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);
            expect(screen.queryByRole("listbox")).toBeNull();
        });

        it("renders OpenStreetMap attribution notice in suggestions listbox", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            expect(screen.getByText(/OpenStreetMap/i)).toBeTruthy();
        });
    });

    describe("3. WAI-ARIA 1.2 Combobox Accessibility", () => {
        it("sets correct ARIA attributes on input when suggestions listbox is closed", () => {
            mockHook({ suggestions: [], status: "IDLE" });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            expect(input.getAttribute("role")).toBe("combobox");
            expect(input.getAttribute("aria-autocomplete")).toBe("list");
            expect(input.getAttribute("aria-expanded")).toBe("false");
            expect(input.getAttribute("aria-controls")).toBeNull();
            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });

        it("sets correct ARIA attributes on input and options when suggestions listbox is open", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("node-2", "100 E Pratt St", "Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const listbox = screen.getByRole("listbox");
            expect(input.getAttribute("aria-expanded")).toBe("true");
            expect(input.getAttribute("aria-controls")).toBe(listbox.id);

            const options = screen.getAllByRole("option");
            expect(options[0].getAttribute("aria-selected")).toBe("false");
            expect(options[1].getAttribute("aria-selected")).toBe("false");
            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });

        it("updates aria-activedescendant and aria-selected during option highlighting", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("node-2", "100 E Pratt St", "Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            let options = screen.getAllByRole("option");
            expect(options[0].getAttribute("aria-selected")).toBe("true");
            expect(options[1].getAttribute("aria-selected")).toBe("false");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[0].id);

            fireEvent.keyDown(input, { key: "ArrowDown" });
            options = screen.getAllByRole("option");
            expect(options[0].getAttribute("aria-selected")).toBe("false");
            expect(options[1].getAttribute("aria-selected")).toBe("true");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[1].id);
        });
    });

    describe("4. Keyboard Navigation", () => {
        it("navigates down through suggestions with ArrowDown with wrap-around", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("node-2", "100 E Pratt St", "Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[1].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");
        });

        it("navigates up through suggestions with ArrowUp with wrap-around", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("node-2", "100 E Pratt St", "Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(options[1].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(options[0].getAttribute("aria-selected")).toBe("true");

            fireEvent.keyDown(input, { key: "ArrowUp" });
            expect(options[1].getAttribute("aria-selected")).toBe("true");
        });

        it("selects highlighted suggestion on Enter and calls handleSelect curried function", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);
            const picked = createSuggestion("node-1", "100 Holliday St", "Baltimore, MD");

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [picked],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            fireEvent.keyDown(input, { key: "Enter" });

            expect(handleSelect).toHaveBeenCalledWith(picked);
            expect(innerSelect).toHaveBeenCalledTimes(1);
        });

        it("does not trigger handleSelect on Enter when no suggestion is highlighted", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            fireEvent.keyDown(input, { key: "Enter" });

            expect(handleSelect).not.toHaveBeenCalled();
            expect(innerSelect).not.toHaveBeenCalled();
        });

        it("resets activeIndex to -1 when user types into the input while dropdown is open", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");

            fireEvent.keyDown(input, { key: "ArrowDown" });
            expect(input.getAttribute("aria-activedescendant")).toBeTruthy();

            fireEvent.change(input, { target: { value: "100 H" } });

            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });

        it("ignores ArrowDown, ArrowUp, and Enter when listbox is closed", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);

            mockHook({
                value: "",
                status: "IDLE",
                suggestions: [],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");

            expect(() => {
                fireEvent.keyDown(input, { key: "ArrowDown" });
                fireEvent.keyDown(input, { key: "ArrowUp" });
                fireEvent.keyDown(input, { key: "Enter" });
            }).not.toThrow();

            expect(handleSelect).not.toHaveBeenCalled();
            expect(innerSelect).not.toHaveBeenCalled();
            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });
    });

    describe("5. Mouse Interaction & Hover", () => {
        it("selects suggestion on mouse click and executes handleSelect", () => {
            const innerSelect = vi.fn<() => void>();
            const handleSelect = vi.fn<(suggestion: AddressSuggestion) => () => void>(() => innerSelect);
            const targetSuggestion = createSuggestion("node-2", "100 E Pratt St", "Baltimore, MD");

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"), targetSuggestion],
                handleSelect,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const options = screen.getAllByRole("option");
            fireEvent.click(options[1]);

            expect(handleSelect).toHaveBeenCalledWith(targetSuggestion);
            expect(innerSelect).toHaveBeenCalledTimes(1);
        });

        it("highlights suggestion on mouseEnter", () => {
            mockHook({
                value: "100",
                status: "OK",
                suggestions: [
                    createSuggestion("node-1", "100 Holliday St", "Baltimore, MD"),
                    createSuggestion("node-2", "100 E Pratt St", "Baltimore, MD"),
                ],
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const options = screen.getAllByRole("option");

            fireEvent.mouseEnter(options[1]);

            expect(options[1].getAttribute("aria-selected")).toBe("true");
            expect(options[0].getAttribute("aria-selected")).toBe("false");
            expect(input.getAttribute("aria-activedescendant")).toBe(options[1].id);
        });
    });

    describe("6. Dismissal Behaviors", () => {
        it("dismisses suggestions and resets activeIndex when Escape is pressed", () => {
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

            fireEvent.keyDown(input, { key: "Escape" });

            expect(clearSuggestions).toHaveBeenCalledTimes(1);
            expect(input.getAttribute("aria-activedescendant")).toBeNull();
        });

        it("dismisses suggestions when user clicks outside the component container", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            render(
                <div>
                    <div data-testid="outside-element">Outside Area</div>
                    <NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />
                </div>,
            );

            expect(screen.getByRole("listbox")).toBeTruthy();

            fireEvent.mouseDown(screen.getByTestId("outside-element"));

            expect(clearSuggestions).toHaveBeenCalledTimes(1);
        });

        it("does not dismiss suggestions when user clicks inside the component container", () => {
            const clearSuggestions = vi.fn<() => void>();

            mockHook({
                value: "100",
                status: "OK",
                suggestions: [createSuggestion("node-1", "100 Holliday St", "Baltimore, MD")],
                clearSuggestions,
            });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");

            fireEvent.mouseDown(input);

            expect(clearSuggestions).not.toHaveBeenCalled();
            expect(screen.getByRole("listbox")).toBeTruthy();
        });
    });

    describe("7. Loading Indicator & Spinners", () => {
        it("renders loading indicator and sets aria-busy=true when hook reports loading=true", () => {
            mockHook({ loading: true });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            expect(input.getAttribute("aria-busy")).toBe("true");
            expect(screen.getByTestId("address-autocomplete-loading")).toBeTruthy();
        });

        it("does not render loading indicator and sets aria-busy=false when hook reports loading=false", () => {
            mockHook({ loading: false });

            render(<NominatimAddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            expect(input.getAttribute("aria-busy")).toBe("false");
            expect(screen.queryByTestId("address-autocomplete-loading")).toBeNull();
        });
    });

    describe("8. Form Error Display & Assistive Tech", () => {
        it("displays error message matching field.name and sets aria-invalid and aria-describedby", () => {
            const form = buildForm({
                errors: { address: "We couldn't verify that address in Maryland." },
            });

            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const alert = screen.getByRole("alert");

            expect(alert.textContent).toContain("We couldn't verify that address in Maryland.");
            expect(input.getAttribute("aria-invalid")).toBe("true");
            expect(input.getAttribute("aria-describedby")).toBe(alert.id);
            expect(alert.id).toBe("address-error");
        });

        it("displays fallback error when form.errors contains an error under another key", () => {
            const form = buildForm({
                errors: { general: "A voter registration lookup error occurred." },
            });

            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");
            const alert = screen.getByRole("alert");

            expect(alert.textContent).toContain("A voter registration lookup error occurred.");
            expect(input.getAttribute("aria-invalid")).toBe("true");
            expect(input.getAttribute("aria-describedby")).toBe(alert.id);
        });

        it("does not render error or invalid attributes when form.errors is empty", () => {
            const form = buildForm({ errors: {} });

            render(<NominatimAddressAutocomplete form={form} field={REGISTRATION_FIELD} />);

            const input = screen.getByRole("combobox");

            expect(screen.queryByRole("alert")).toBeNull();
            expect(input.getAttribute("aria-invalid")).toBe("false");
            expect(input.getAttribute("aria-describedby")).toBeNull();
        });
    });
});
