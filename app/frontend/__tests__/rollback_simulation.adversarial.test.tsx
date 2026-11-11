// @lat: [[locale-extension#Nominatim geographic configuration]]
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import type { InertiaFormProps } from "@inertiajs/react";
import type { sway } from "sway";

import { useJsApiLoader } from "@react-google-maps/api";

import AddressAutocomplete from "app/frontend/components/user/AddressAutocomplete";
import {
    useAddressAutocomplete,
    placePredictionToSuggestion,
    type AddressSuggestion,
    type UseAddressAutocomplete,
} from "app/frontend/hooks/useAddressAutocomplete";
import {
    parseGoogleAddressComponents,
    type TParsedGoogleAddress,
} from "app/frontend/sway_utils/parseGoogleAddressComponents";

const useJsApiLoaderMock = vi.fn<() => { isLoaded: boolean; loadError: undefined }>(() => ({
    isLoaded: true,
    loadError: undefined,
}));

vi.mock("@react-google-maps/api", () => ({
    useJsApiLoader: () => useJsApiLoaderMock(),
}));

const mockUseAddressAutocomplete = vi.fn<() => UseAddressAutocomplete>(() => ({
    value: "100 Holliday St",
    status: "OK",
    suggestions: [
        {
            place_id: "google-place-1",
            description: "100 Holliday St, Baltimore, MD, USA",
            structured_formatting: {
                main_text: "100 Holliday St",
                secondary_text: "Baltimore, MD, USA",
            },
        },
    ],
    loading: false,
    handleInput: vi.fn<() => void>(),
    handleSelect: vi.fn<(_s: AddressSuggestion) => () => void>(() => vi.fn<() => void>()),
    clearSuggestions: vi.fn<() => void>(),
}));

vi.mock("app/frontend/hooks/useAddressAutocomplete", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/hooks/useAddressAutocomplete")>();
    return {
        ...actual,
        useAddressAutocomplete: () => mockUseAddressAutocomplete(),
    };
});

describe("Empirical Rollback Simulation & Google Maps Deprecation Parity", () => {
    const REGISTRATION_FIELD: sway.IFormField<sway.IUser> = {
        name: "address",
        component: "text",
        type: "text",
        label: "Street Address",
        isRequired: true,
    };

    it("verifies Google Maps package dependencies exist and export expected functions", () => {
        expect(useJsApiLoader).toBeDefined();
        expect(typeof useJsApiLoader).toBe("function");
    });

    it("verifies deprecated Google Maps utilities and hooks export expected interfaces and functions", () => {
        expect(useAddressAutocomplete).toBeDefined();
        expect(typeof useAddressAutocomplete).toBe("function");
        expect(placePredictionToSuggestion).toBeDefined();
        expect(typeof placePredictionToSuggestion).toBe("function");
        expect(parseGoogleAddressComponents).toBeDefined();
        expect(typeof parseGoogleAddressComponents).toBe("function");
        expect(AddressAutocomplete).toBeDefined();
        expect(typeof AddressAutocomplete).toBe("function");
    });

    it("simulates full rollback: renders legacy AddressAutocomplete with Sway registration form props", () => {
        const mockForm = {
            data: { address: "100 Holliday St" },
            errors: {},
            setData: vi.fn<(k: string, v: unknown) => void>(),
        } as unknown as InertiaFormProps<Record<string, unknown>>;

        const setLoading = vi.fn<(l: boolean) => void>();

        render(<AddressAutocomplete form={mockForm} field={REGISTRATION_FIELD} setLoading={setLoading} />);

        const input = screen.getByLabelText("Street Address");
        expect(input).toBeInTheDocument();
        expect(input.getAttribute("role")).toBe("combobox");

        expect(screen.getByRole("listbox")).toBeInTheDocument();
        expect(screen.getByText("100 Holliday St")).toBeInTheDocument();
        expect(screen.getByText("Baltimore, MD, USA")).toBeInTheDocument();
    });

    it("verifies parseGoogleAddressComponents parses complete legacy place structure into sway address shape", () => {
        const mockPlace = {
            addressComponents: [
                { longText: "100", shortText: "100", types: ["street_number"] },
                { longText: "Holliday Street", shortText: "Holliday St", types: ["route"] },
                { longText: "Baltimore", shortText: "Baltimore", types: ["locality"] },
                { longText: "Maryland", shortText: "MD", types: ["administrative_area_level_1"] },
                { longText: "21202", shortText: "21202", types: ["postal_code"] },
                { longText: "United States", shortText: "US", types: ["country"] },
            ],
            location: {
                lat: () => 39.2904,
                lng: () => -76.6122,
            },
        } as unknown as google.maps.places.Place;

        const parsed: TParsedGoogleAddress = parseGoogleAddressComponents(mockPlace);

        expect(parsed).toEqual({
            street: "100 Holliday Street",
            city: "Baltimore",
            region: "Maryland",
            region_code: "MD",
            postal_code: "21202",
            country: "United States",
            latitude: 39.2904,
            longitude: -76.6122,
        });
    });
});
