// @lat: [[locale-extension#Nominatim geographic configuration]]
import type { InertiaFormProps } from "@inertiajs/react";
import { useCallback, useMemo, useRef, useState } from "react";
import type { sway } from "sway";

import { logDev } from "app/frontend/sway_utils";
import { parseGoogleAddressComponents } from "app/frontend/sway_utils/parseGoogleAddressComponents";

// @lat: [[address-autocomplete-hook-design#Why the suggestion shape mirrors the old use-places-autocomplete library]]
export interface AddressSuggestion {
    place_id: string;
    description: string;
    structured_formatting: {
        main_text: string;
        secondary_text: string;
    };
}

export interface UseAddressAutocomplete {
    value: string;
    status: string;
    suggestions: AddressSuggestion[];
    loading: boolean;
    handleInput: (e: React.ChangeEvent<HTMLInputElement>) => void;
    handleSelect: (suggestion: AddressSuggestion) => () => void;
    clearSuggestions: () => void;
}

const DEBOUNCE_MS = 1000;

// @lat: [[address-autocomplete-hook-design#Why the suggestion shape mirrors the old use-places-autocomplete library]]
export const placePredictionToSuggestion = (prediction: google.maps.places.PlacePrediction): AddressSuggestion => ({
    place_id: prediction.placeId,
    description: prediction.text.text,
    structured_formatting: {
        main_text: prediction.mainText?.text ?? prediction.text.text,
        secondary_text: prediction.secondaryText?.text ?? "",
    },
});

const isEmptyAddress = (address: Partial<sway.IAddress>): boolean => {
    return !(address.street || address.city) || !address.region_code || !address.postal_code;
};

// @lat: [[address-autocomplete-hook-design#Why the suggestion shape mirrors the old use-places-autocomplete library]]
export const useAddressAutocomplete = <TForm extends Partial<sway.IAddress> = Partial<sway.IAddress>>(
    form: InertiaFormProps<TForm>,
    setLoading: (l: boolean) => void,
): UseAddressAutocomplete => {
    const { data, setData } = form;
    const address = data as Partial<sway.IAddress>;

    const defaultValue = useMemo(
        () =>
            isEmptyAddress(address)
                ? ""
                : `${address.street ?? ""} ${address.city ?? ""}, ${address.region_code ?? ""}, ${address.postal_code ?? ""}`,
        [address],
    );

    const [value, setValue] = useState(defaultValue);
    const [suggestions, setSuggestions] = useState<AddressSuggestion[]>([]);
    const [status, setStatus] = useState("");
    const [loading, setPredicting] = useState(false);

    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const sessionTokenRef = useRef<google.maps.places.AutocompleteSessionToken | null>(null);
    const requestIdRef = useRef(0);
    // @lat: [[address-autocomplete-hook-design#Why the suggestion shape mirrors the old use-places-autocomplete library]]
    const predictionsRef = useRef(new Map<string, google.maps.places.PlacePrediction>());

    const clearSuggestions = useCallback(() => {
        setSuggestions([]);
        setStatus("");
    }, []);

    const fetchSuggestions = useCallback(async (input: string) => {
        const requestId = ++requestIdRef.current;
        if (!sessionTokenRef.current) {
            sessionTokenRef.current = new google.maps.places.AutocompleteSessionToken();
        }
        setPredicting(true);
        try {
            const { suggestions: results } =
                await google.maps.places.AutocompleteSuggestion.fetchAutocompleteSuggestions({
                    input,
                    sessionToken: sessionTokenRef.current,
                    includedRegionCodes: ["us"],
                });
            // @lat: [[address-autocomplete-hook-design#Why state lives in refs instead of useEffect]]
            if (requestId !== requestIdRef.current) return;
            predictionsRef.current.clear();
            const mapped: AddressSuggestion[] = [];
            for (const { placePrediction } of results) {
                if (!placePrediction) continue;
                predictionsRef.current.set(placePrediction.placeId, placePrediction);
                mapped.push(placePredictionToSuggestion(placePrediction));
            }
            setSuggestions(mapped);
            setStatus(mapped.length > 0 ? "OK" : "ZERO_RESULTS");
        } catch (e) {
            if (requestId !== requestIdRef.current) return;
            console.error("useAddressAutocomplete.fetchSuggestions", e);
            setSuggestions([]);
            setStatus("ERROR");
        } finally {
            if (requestId === requestIdRef.current) setPredicting(false);
        }
    }, []);

    const handleInput = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const input = e.target.value;
            setValue(input);
            if (debounceRef.current) clearTimeout(debounceRef.current);
            if (input.trim() === "") {
                // @lat: [[address-autocomplete-hook-design#Why state lives in refs instead of useEffect]]
                requestIdRef.current++;
                clearSuggestions();
                return;
            }
            debounceRef.current = setTimeout(() => fetchSuggestions(input), DEBOUNCE_MS);
        },
        [clearSuggestions, fetchSuggestions],
    );

    const handleSelect = useCallback(
        (suggestion: AddressSuggestion) => () => {
            setLoading(true);
            logDev("useAddressAutocomplete.handleSelect - SELECTED ADDRESS -", suggestion);

            if (debounceRef.current) clearTimeout(debounceRef.current);
            // @lat: [[address-autocomplete-hook-design#Why state lives in refs instead of useEffect]]
            requestIdRef.current++;
            setValue(suggestion.description);

            const prediction = predictionsRef.current.get(suggestion.place_id);
            clearSuggestions();

            if (!prediction) {
                console.error("useAddressAutocomplete.handleSelect - no prediction for", suggestion.place_id);
                sessionTokenRef.current = null;
                setLoading(false);
                return;
            }

            // @lat: [[address-place-classification#Why the web autocomplete's request for types costs nothing extra]]
            prediction
                .toPlace()
                .fetchFields({ fields: ["addressComponents", "location", "types"] })
                .then(({ place }) => {
                    logDev("useAddressAutocomplete.fetchFields - PLACE -", place);
                    const parsed = parseGoogleAddressComponents(place);
                    const setField = setData as (key: string, val: unknown) => void;
                    Object.entries(parsed).forEach(([key, val]) => setField(key, val));
                    setField("place_types", place.types ?? []);
                })
                .catch((e) => console.error(e))
                .finally(() => {
                    // @lat: [[address-autocomplete-hook-design#Why state lives in refs instead of useEffect]]
                    sessionTokenRef.current = null;
                    setLoading(false);
                });
        },
        [clearSuggestions, setData, setLoading],
    );

    return { value, status, suggestions, loading, handleInput, handleSelect, clearSuggestions };
};
