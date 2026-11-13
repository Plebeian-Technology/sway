import type { InertiaFormProps } from "@inertiajs/react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { sway } from "sway";

import { logDev } from "app/frontend/sway_utils";
import { type INominatimPlace, parseNominatimAddress } from "app/frontend/sway_utils/parseNominatimAddress";

export interface AddressSuggestion {
    place_id: string;
    description: string;
    structured_formatting: {
        main_text: string;
        secondary_text: string;
    };
    raw_place?: INominatimPlace;
}

export interface UseNominatimAddressAutocomplete {
    value: string;
    status: string;
    suggestions: AddressSuggestion[];
    loading: boolean;
    handleInput: (e: React.ChangeEvent<HTMLInputElement>) => void;
    handleSelect: (suggestion: AddressSuggestion) => () => void;
    clearSuggestions: () => void;
}

export const NOMINATIM_DEBOUNCE_MS = 1000;

const SELECTED_ADDRESS_FIELDS = [
    "street",
    "city",
    "region",
    "region_code",
    "postal_code",
    "country",
    "latitude",
    "longitude",
    "place_types",
];
export const NOMINATIM_SEARCH_ENDPOINT = "/addresses/autocomplete";
export const NOMINATIM_USER_AGENT = "Sway/1.0 (civic-tech-app; https://sway.vote)";

export const nominatimPlaceToSuggestion = (place: INominatimPlace): AddressSuggestion => {
    const placeId = String(place.place_id ?? "");
    const displayName = typeof place.display_name === "string" ? place.display_name.trim() : "";
    const address = place.address;

    let mainText = "";
    let secondaryText = "";

    if (address) {
        const houseNumber = address.house_number ? String(address.house_number).trim() : "";
        const road = (
            address.road ??
            address.street ??
            address.pedestrian ??
            address.square ??
            address.footway ??
            address.cycleway ??
            address.path ??
            ""
        )
            .toString()
            .trim();

        if (houseNumber && road) {
            mainText = `${houseNumber} ${road}`;
        } else if (road) {
            mainText = road;
        } else if (typeof place.name === "string" && place.name.trim().length > 0) {
            mainText = place.name.trim();
        }
    }

    if (!displayName) {
        return {
            place_id: placeId,
            description: "",
            structured_formatting: {
                main_text: mainText,
                secondary_text: "",
            },
        };
    }

    const parts = displayName
        .split(",")
        .map((p) => p.trim())
        .filter(Boolean);

    if (!mainText) {
        mainText = parts[0] ?? "";
        secondaryText = parts.slice(1).join(", ");
    } else {
        if (displayName.startsWith(mainText)) {
            secondaryText = displayName.slice(mainText.length).replace(/^,\s*/, "").trim();
        } else if (
            parts.length > 1 &&
            parts[0] === (address?.house_number ? String(address.house_number).trim() : "") &&
            parts[1] === (address?.road ? String(address.road).trim() : "")
        ) {
            secondaryText = parts.slice(2).join(", ");
        } else {
            const matchedIndex = parts.findIndex((p) => p.toLowerCase() === mainText.toLowerCase());
            if (matchedIndex >= 0) {
                secondaryText = [...parts.slice(0, matchedIndex), ...parts.slice(matchedIndex + 1)].join(", ");
            } else {
                secondaryText = parts.slice(1).join(", ");
            }
        }
    }

    return {
        place_id: placeId,
        description: displayName,
        structured_formatting: {
            main_text: mainText,
            secondary_text: secondaryText,
        },
    };
};

// @lat: [[locale-extension#Nominatim geographic configuration]]
export const buildNominatimUrl = (query: string, locale?: sway.ISwayLocale | null): string => {
    const base =
        typeof window !== "undefined" && window.location?.origin ? window.location.origin : "https://sway.vote";
    const url = new URL(NOMINATIM_SEARCH_ENDPOINT, base);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("addressdetails", "1");
    url.searchParams.set("limit", "5");
    url.searchParams.set("q", query);

    if (locale?.nominatim_viewbox) {
        const viewbox = locale.nominatim_viewbox.trim();
        if (viewbox) {
            url.searchParams.set("viewbox", viewbox);
            if (locale.nominatim_bounded !== undefined && locale.nominatim_bounded !== null) {
                url.searchParams.set("bounded", locale.nominatim_bounded ? "1" : "0");
            }
        }
    }

    if (locale?.nominatim_country_codes) {
        const countryCodes = locale.nominatim_country_codes.trim();
        if (countryCodes) {
            url.searchParams.set("countrycodes", countryCodes.toLowerCase());
        }
    }

    return url.toString().replace(/\+/g, "%20");
};

const isEmptyAddress = (address?: Partial<sway.IAddress> | null): boolean => {
    if (!address) return true;
    return !(address.street || address.city) || !address.region_code || !address.postal_code;
};

export function isAbortError(e: unknown): boolean {
    if (e instanceof Error && e.name === "AbortError") {
        return true;
    }
    if (typeof DOMException !== "undefined" && e instanceof DOMException && e.name === "AbortError") {
        return true;
    }
    return typeof e === "object" && e !== null && "name" in e && (e as { name: unknown }).name === "AbortError";
}

// @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
export function useNominatimAddressAutocomplete<TForm extends object = Record<string, unknown>>(
    form: InertiaFormProps<TForm>,
    setLoading?: (loading: boolean) => void,
    locale?: sway.ISwayLocale | null,
): UseNominatimAddressAutocomplete {
    const { data, setData } = form;
    const address = data as unknown as Partial<sway.IAddress>;

    const defaultValue = useMemo(
        () =>
            isEmptyAddress(address)
                ? ""
                : `${address.street ?? ""} ${address.city ?? ""}, ${address.region_code ?? ""}, ${address.postal_code ?? ""}`.trim(),
        [address],
    );

    const [value, setValue] = useState(defaultValue);
    const [suggestions, setSuggestions] = useState<AddressSuggestion[]>([]);
    const [status, setStatus] = useState("IDLE");
    const [loading, setInternalLoading] = useState(false);

    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const abortControllerRef = useRef<AbortController | null>(null);
    const requestIdRef = useRef(0);
    const placesRef = useRef<Map<string, INominatimPlace>>(new Map());

    const updateLoading = useCallback(
        (isLoading: boolean) => {
            setInternalLoading(isLoading);
            setLoading?.(isLoading);
        },
        [setLoading],
    );

    const clearSuggestions = useCallback(() => {
        if (debounceRef.current) {
            clearTimeout(debounceRef.current);
            debounceRef.current = null;
        }
        requestIdRef.current++;
        if (abortControllerRef.current) {
            abortControllerRef.current.abort();
            abortControllerRef.current = null;
        }
        placesRef.current.clear();
        setSuggestions([]);
        setStatus("");
        updateLoading(false);
    }, [updateLoading]);

    const fetchSuggestions = useCallback(
        async (query: string) => {
            const requestId = ++requestIdRef.current;

            if (abortControllerRef.current) {
                abortControllerRef.current.abort();
            }
            const abortController = new AbortController();
            abortControllerRef.current = abortController;

            updateLoading(true);

            try {
                const url = buildNominatimUrl(query, locale);

                const response = await fetch(url, {
                    signal: abortController.signal,
                    headers: {
                        "User-Agent": NOMINATIM_USER_AGENT,
                        Accept: "application/json",
                    },
                });

                if (requestId !== requestIdRef.current) return;

                if (!response.ok) {
                    placesRef.current.clear();
                    setSuggestions([]);
                    setStatus("ERROR");
                    return;
                }

                const json: unknown = await response.json();
                if (requestId !== requestIdRef.current) return;

                if (!Array.isArray(json)) {
                    placesRef.current.clear();
                    setSuggestions([]);
                    setStatus("ERROR");
                    return;
                }

                if (json.length === 0) {
                    placesRef.current.clear();
                    setSuggestions([]);
                    setStatus("ZERO_RESULTS");
                    return;
                }

                placesRef.current.clear();
                const mapped: AddressSuggestion[] = [];

                for (const item of json as INominatimPlace[]) {
                    if (!item || typeof item !== "object") continue;
                    const suggestion = nominatimPlaceToSuggestion(item);
                    placesRef.current.set(suggestion.place_id, item);
                    mapped.push(suggestion);
                }

                setSuggestions(mapped);
                setStatus("OK");
            } catch (e: unknown) {
                if (isAbortError(e)) {
                    return;
                }
                if (requestId !== requestIdRef.current) return;
                logDev("useNominatimAddressAutocomplete.fetchSuggestions error:", e);
                placesRef.current.clear();
                setSuggestions([]);
                setStatus("ERROR");
            } finally {
                if (requestId === requestIdRef.current) {
                    updateLoading(false);
                }
            }
        },
        [locale, updateLoading],
    );

    // @lat: [[registration-dead-ends#Submitting the typed address when no complete suggestion is picked]]
    const handleInput = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const input = e.target.value;
            setValue(input);
            const setField = setData as (key: string, val: unknown) => void;
            setField("typed_address", input);
            SELECTED_ADDRESS_FIELDS.forEach((field) => setField(field, undefined));

            if (debounceRef.current) {
                clearTimeout(debounceRef.current);
                debounceRef.current = null;
            }

            const trimmed = input.trim();
            if (trimmed === "") {
                requestIdRef.current++;
                if (abortControllerRef.current) {
                    abortControllerRef.current.abort();
                    abortControllerRef.current = null;
                }
                placesRef.current.clear();
                setSuggestions([]);
                setStatus("IDLE");
                updateLoading(false);
                return;
            }

            debounceRef.current = setTimeout(() => {
                fetchSuggestions(trimmed).catch(() => {});
            }, NOMINATIM_DEBOUNCE_MS);
        },
        [fetchSuggestions, setData, updateLoading],
    );

    // @lat: [[address-place-classification#Why the web autocomplete's request for types costs nothing extra]]
    const handleSelect = useCallback(
        (suggestion: AddressSuggestion) => () => {
            updateLoading(true);
            logDev("useNominatimAddressAutocomplete.handleSelect - SELECTED ADDRESS -", suggestion);

            if (debounceRef.current) {
                clearTimeout(debounceRef.current);
                debounceRef.current = null;
            }
            requestIdRef.current++;
            if (abortControllerRef.current) {
                abortControllerRef.current.abort();
                abortControllerRef.current = null;
            }

            const place = placesRef.current.get(suggestion.place_id) ?? suggestion.raw_place;
            setValue(suggestion.description);
            clearSuggestions();

            const setField = setData as (key: string, val: unknown) => void;
            setField("typed_address", suggestion.description);
            const parsed: Record<string, unknown> = place ? parseNominatimAddress(place) : {};
            SELECTED_ADDRESS_FIELDS.forEach((field) => setField(field, parsed[field]));
            if (place) {
                const placeTypes = [place.type, place.class ?? place.category].filter(
                    (t): t is string => typeof t === "string" && t.length > 0,
                );
                setField("place_types", placeTypes);
            }

            updateLoading(false);
        },
        [clearSuggestions, setData, updateLoading],
    );

    useEffect(() => {
        return () => {
            if (debounceRef.current) {
                clearTimeout(debounceRef.current);
                debounceRef.current = null;
            }
            if (abortControllerRef.current) {
                abortControllerRef.current.abort();
                abortControllerRef.current = null;
            }
        };
    }, []);

    return {
        value,
        status,
        suggestions,
        loading,
        handleInput,
        handleSelect,
        clearSuggestions,
    };
}
