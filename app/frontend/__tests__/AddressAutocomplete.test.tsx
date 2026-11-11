import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// ── Module mocks ────────────────────────────────────────────────────────────

const useJsApiLoaderMock = vi.fn<(...args: unknown[]) => unknown>();
vi.mock("@react-google-maps/api", () => ({
    useJsApiLoader: (...a: unknown[]) => useJsApiLoaderMock(...a),
}));

// @lat: [[frontend-test-infrastructure-notes#AddressAutocomplete: mocking the hook, not the API]]
const useAddressAutocompleteMock = vi.fn<(...args: unknown[]) => unknown>();
vi.mock("app/frontend/hooks/useAddressAutocomplete", () => ({
    useAddressAutocomplete: (...a: unknown[]) => useAddressAutocompleteMock(...a),
}));

import AddressAutocomplete from "app/frontend/components/user/AddressAutocomplete";
import type { AddressSuggestion } from "app/frontend/hooks/useAddressAutocomplete";
import type { InertiaFormProps } from "@inertiajs/react";
import type { sway } from "sway";

type TestForm = InertiaFormProps<Record<string, unknown>>;

// ── Helpers ────────────────────────────────────────────────────────────────

const REGISTRATION_FIELD: sway.IFormField<sway.IUser> = {
    name: "address",
    component: "text",
    type: "text",
    label: "Address",
    isRequired: true,
};

function buildForm(overrides: Record<string, unknown> = {}) {
    return {
        data: {},
        errors: {},
        setData: vi.fn<() => void>(),
        ...overrides,
    } as unknown as TestForm;
}

const suggestion = (place_id: string, main: string, secondary: string): AddressSuggestion => ({
    place_id,
    description: `${main}, ${secondary}`,
    structured_formatting: { main_text: main, secondary_text: secondary },
});

function mockHook(overrides: Partial<ReturnType<typeof useAddressAutocompleteMock>> = {}) {
    useAddressAutocompleteMock.mockReturnValue({
        value: "",
        status: "",
        suggestions: [],
        loading: false,
        handleInput: vi.fn<() => void>(),
        handleSelect: vi.fn<() => () => void>(() => vi.fn<() => void>()),
        clearSuggestions: vi.fn<() => void>(),
        ...overrides,
    });
}

// ── Tests ──────────────────────────────────────────────────────────────────

describe("AddressAutocomplete (AutocompleteSuggestion migration)", () => {
    beforeEach(() => {
        useJsApiLoaderMock.mockReset();
        useAddressAutocompleteMock.mockReset();
        mockHook();
    });

    afterEach(() => {
        cleanup();
    });

    it("renders the loading skeleton while the Google Maps SDK is loading", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: false });

        render(<AddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} setLoading={vi.fn<() => void>()} />);

        expect(screen.getByTestId("address-autocomplete-skeleton")).toBeTruthy();
    });

    it("renders the labeled input once the SDK is loaded", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: true });

        render(<AddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} setLoading={vi.fn<() => void>()} />);

        expect(screen.getByLabelText("Address")).toBeTruthy();
        expect(screen.queryByTestId("address-autocomplete-skeleton")).toBeNull();
    });

    it("renders suggestions when the hook reports status='OK'", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: true });
        mockHook({
            value: "1 W",
            status: "OK",
            suggestions: [suggestion("abc", "1 W Elm St", "Baltimore, MD")],
        });

        render(<AddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} setLoading={vi.fn<() => void>()} />);

        expect(screen.getByRole("listbox")).toBeTruthy();
        expect(screen.getByText("1 W Elm St")).toBeTruthy();
        expect(screen.getByText("Baltimore, MD")).toBeTruthy();
    });

    it("forwards typing to the hook's handleInput", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: true });
        const handleInput = vi.fn<() => void>();
        mockHook({ handleInput });

        render(<AddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} setLoading={vi.fn<() => void>()} />);

        fireEvent.change(screen.getByLabelText("Address"), { target: { value: "1 W Elm" } });

        expect(handleInput).toHaveBeenCalledTimes(1);
    });

    it("exposes combobox ARIA and navigates suggestions with the keyboard", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: true });
        mockHook({
            value: "1 W",
            status: "OK",
            suggestions: [
                suggestion("abc", "1 W Elm St", "Baltimore, MD"),
                suggestion("def", "1 W Oak St", "Baltimore, MD"),
            ],
        });

        render(<AddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} setLoading={vi.fn<() => void>()} />);

        const input = screen.getByRole("combobox");
        expect(input.getAttribute("aria-expanded")).toBe("true");
        expect(input.getAttribute("aria-activedescendant")).toBeNull();
        expect(screen.getAllByRole("option")).toHaveLength(2);

        fireEvent.keyDown(input, { key: "ArrowDown" });
        let options = screen.getAllByRole("option");
        expect(options[0].getAttribute("aria-selected")).toBe("true");
        expect(input.getAttribute("aria-activedescendant")).toBe(options[0].id);

        fireEvent.keyDown(input, { key: "ArrowDown" });
        options = screen.getAllByRole("option");
        expect(options[1].getAttribute("aria-selected")).toBe("true");
        expect(input.getAttribute("aria-activedescendant")).toBe(options[1].id);
    });

    it("selects the highlighted suggestion on Enter", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: true });
        const inner = vi.fn<() => void>();
        const handleSelect = vi.fn<() => typeof inner>(() => inner);
        const picked = suggestion("abc", "1 W Elm St", "Baltimore, MD");
        mockHook({ value: "1 W", status: "OK", suggestions: [picked], handleSelect });

        render(<AddressAutocomplete form={buildForm()} field={REGISTRATION_FIELD} setLoading={vi.fn<() => void>()} />);

        const input = screen.getByRole("combobox");
        fireEvent.keyDown(input, { key: "ArrowDown" });
        fireEvent.keyDown(input, { key: "Enter" });

        expect(handleSelect).toHaveBeenCalledWith(picked);
        expect(inner).toHaveBeenCalledTimes(1);
    });

    it("links a submit error to the input for assistive tech", () => {
        useJsApiLoaderMock.mockReturnValue({ isLoaded: true });

        render(
            <AddressAutocomplete
                form={buildForm({ errors: { address: "We couldn't verify that address." } })}
                field={REGISTRATION_FIELD}
                setLoading={vi.fn<() => void>()}
            />,
        );

        const input = screen.getByRole("combobox");
        const error = screen.getByRole("alert");
        expect(error.textContent).toContain("We couldn't verify that address.");
        expect(input.getAttribute("aria-invalid")).toBe("true");
        expect(input.getAttribute("aria-describedby")).toBe(error.id);
    });
});
