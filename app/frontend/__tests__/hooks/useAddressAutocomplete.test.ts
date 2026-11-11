import { act, renderHook } from "@testing-library/react";
import type { InertiaFormProps } from "@inertiajs/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { placePredictionToSuggestion, useAddressAutocomplete } from "app/frontend/hooks/useAddressAutocomplete";

// Small fake objects shaped like a Google PlacePrediction, because the real
// google.maps code is not loaded under vitest. Only the fields the converter
// reads are filled in.
const prediction = (overrides: Partial<google.maps.places.PlacePrediction> = {}): google.maps.places.PlacePrediction =>
    ({
        placeId: "place-123",
        text: { text: "1 W Elm St, Baltimore, MD, USA" },
        mainText: { text: "1 W Elm St" },
        secondaryText: { text: "Baltimore, MD, USA" },
        ...overrides,
    }) as unknown as google.maps.places.PlacePrediction;

describe("placePredictionToSuggestion", () => {
    it("maps a PlacePrediction to the AddressSuggestion the field renders", () => {
        expect(placePredictionToSuggestion(prediction())).toEqual({
            place_id: "place-123",
            description: "1 W Elm St, Baltimore, MD, USA",
            structured_formatting: {
                main_text: "1 W Elm St",
                secondary_text: "Baltimore, MD, USA",
            },
        });
    });

    it("falls back to the full text when mainText is missing, and to '' for secondaryText", () => {
        const result = placePredictionToSuggestion(prediction({ mainText: null, secondaryText: null }));

        expect(result.structured_formatting.main_text).toBe("1 W Elm St, Baltimore, MD, USA");
        expect(result.structured_formatting.secondary_text).toBe("");
    });
});

// The 1000ms debounce inside useAddressAutocomplete's handleInput.
const DEBOUNCE_MS = 1000;

describe("useAddressAutocomplete — handleSelect fetches and forwards place types", () => {
    const fetchFieldsMock = vi.fn<(args: { fields: string[] }) => Promise<{ place: google.maps.places.Place }>>();
    const toPlaceMock = vi.fn<() => { fetchFields: typeof fetchFieldsMock }>(() => ({ fetchFields: fetchFieldsMock }));
    const fetchAutocompleteSuggestionsMock =
        vi.fn<() => Promise<{ suggestions: { placePrediction: google.maps.places.PlacePrediction }[] }>>();

    beforeEach(() => {
        fetchFieldsMock.mockReset();
        toPlaceMock.mockClear();
        fetchAutocompleteSuggestionsMock.mockReset();
        fetchAutocompleteSuggestionsMock.mockResolvedValue({
            suggestions: [{ placePrediction: prediction({ toPlace: toPlaceMock } as never) }],
        });
        vi.stubGlobal("google", {
            maps: {
                places: {
                    AutocompleteSessionToken: class {},
                    AutocompleteSuggestion: { fetchAutocompleteSuggestions: fetchAutocompleteSuggestionsMock },
                },
            },
        });
        vi.useFakeTimers();
    });

    afterEach(() => {
        vi.useRealTimers();
        vi.unstubAllGlobals();
    });

    const selectTheOnlySuggestion = async (
        form: InertiaFormProps<Record<string, unknown>>,
        setLoading = vi.fn<(l: boolean) => void>(),
    ) => {
        const { result } = renderHook(() => useAddressAutocomplete(form, setLoading));

        act(() => {
            result.current.handleInput({ target: { value: "1 W Elm" } } as React.ChangeEvent<HTMLInputElement>);
        });
        await act(async () => {
            await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
        });

        act(() => {
            result.current.handleSelect(result.current.suggestions[0])();
        });
        await act(async () => {
            await vi.advanceTimersByTimeAsync(0);
        });
    };

    it("requests the types field alongside addressComponents and location", async () => {
        fetchFieldsMock.mockResolvedValue({ place: { addressComponents: [], location: null, types: [] } as never });
        const form = {
            data: {},
            setData: vi.fn<(k: string, v: unknown) => void>(),
        } as unknown as InertiaFormProps<Record<string, unknown>>;

        await selectTheOnlySuggestion(form);

        expect(fetchFieldsMock).toHaveBeenCalledWith({ fields: ["addressComponents", "location", "types"] });
    });

    it("forwards the place types Google returns onto the form as place_types", async () => {
        fetchFieldsMock.mockResolvedValue({
            place: { addressComponents: [], location: null, types: ["street_address", "premise"] } as never,
        });
        const setData = vi.fn<(k: string, v: unknown) => void>();
        const form = { data: {}, setData } as unknown as InertiaFormProps<Record<string, unknown>>;

        await selectTheOnlySuggestion(form);

        expect(setData).toHaveBeenCalledWith("place_types", ["street_address", "premise"]);
    });

    it("forwards an empty list when Google returns no types", async () => {
        fetchFieldsMock.mockResolvedValue({
            place: { addressComponents: [], location: null, types: undefined } as never,
        });
        const setData = vi.fn<(k: string, v: unknown) => void>();
        const form = { data: {}, setData } as unknown as InertiaFormProps<Record<string, unknown>>;

        await selectTheOnlySuggestion(form);

        expect(setData).toHaveBeenCalledWith("place_types", []);
    });
});
