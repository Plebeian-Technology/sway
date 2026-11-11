// @lat: [[mobile-address-autocomplete-design#Why the native SDK instead of a plain fetch]]
import React, { useCallback, useEffect, useRef, useState } from "react";
import { ActivityIndicator, Pressable, Text, TextInput, View } from "react-native";
import GooglePlacesSDK, { PlacePrediction, Place, PLACE_FIELDS } from "react-native-google-places-sdk";

const DEBOUNCE_MS = 250;
// @lat: [[mobile-address-autocomplete-design#MIN_QUERY_CHARS]]
const MIN_QUERY_CHARS = 3;

export interface ParsedAddress {
    street1: string;
    street2: string;
    city: string;
    region_code: string;
    postal_code: string;
    country: string;
    latitude: number | null;
    longitude: number | null;
    formatted: string;
    place_types: string[];
}

interface Props {
    initialValue?: string;
    onSelect: (parsed: ParsedAddress) => void;
    onError: (message: string) => void;
}

function pickComponent(
    components: Place["addressComponents"],
    type: string,
    field: "name" | "shortName" = "name",
): string {
    return components?.find((c) => c.types.includes(type))?.[field] ?? "";
}

function parsePlace(place: Place): ParsedAddress {
    const c = place.addressComponents;
    const streetNumber = pickComponent(c, "street_number");
    const route = pickComponent(c, "route");
    return {
        street1: [streetNumber, route].filter(Boolean).join(" "),
        street2: pickComponent(c, "subpremise"),
        city: pickComponent(c, "locality") || pickComponent(c, "sublocality") || pickComponent(c, "postal_town"),
        region_code: pickComponent(c, "administrative_area_level_1", "shortName"),
        postal_code: pickComponent(c, "postal_code"),
        country: pickComponent(c, "country") || "United States",
        latitude: place.coordinate?.latitude ?? null,
        longitude: place.coordinate?.longitude ?? null,
        formatted: place.formattedAddress ?? "",
        place_types: place.types ?? [],
    };
}

export default function AddressAutocomplete({ initialValue = "", onSelect, onError }: Props) {
    const [query, setQuery] = useState(initialValue);
    const [predictions, setPredictions] = useState<PlacePrediction[]>([]);
    const [loading, setLoading] = useState(false);
    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const requestSeqRef = useRef(0);
    // @lat: [[mobile-address-autocomplete-design#selectedDescription reopen guard]]
    const [selectedDescription, setSelectedDescription] = useState<string | null>(null);

    const fetchPredictions = useCallback(
        async (input: string) => {
            if (input.trim().length < MIN_QUERY_CHARS) {
                setPredictions([]);
                return;
            }
            const seq = ++requestSeqRef.current;
            setLoading(true);
            try {
                const results = await GooglePlacesSDK.fetchPredictions(input, {
                    types: ["address"],
                    countries: ["us"],
                });
                if (seq !== requestSeqRef.current) return;
                setPredictions(results);
            } catch (e) {
                if (seq !== requestSeqRef.current) return;
                onError(e instanceof Error ? e.message : "Address lookup failed.");
                setPredictions([]);
            } finally {
                if (seq === requestSeqRef.current) setLoading(false);
            }
        },
        [onError],
    );

    useEffect(() => {
        if (debounceRef.current) clearTimeout(debounceRef.current);
        if (selectedDescription !== null && query === selectedDescription) {
            setPredictions([]);
            return;
        }
        debounceRef.current = setTimeout(() => void fetchPredictions(query), DEBOUNCE_MS);
        return () => {
            if (debounceRef.current) clearTimeout(debounceRef.current);
        };
    }, [query, fetchPredictions, selectedDescription]);

    const onPick = useCallback(
        async (placeID: string, description: string) => {
            setSelectedDescription(description);
            setQuery(description);
            setPredictions([]);
            setLoading(true);
            try {
                const place = await GooglePlacesSDK.fetchPlaceByID(placeID, [
                    PLACE_FIELDS.ADDRESS_COMPONENTS,
                    PLACE_FIELDS.FORMATTED_ADDRESS,
                    PLACE_FIELDS.COORDINATE,
                    PLACE_FIELDS.TYPES,
                ]);
                onSelect(parsePlace(place));
            } catch (e) {
                onError(e instanceof Error ? e.message : "Could not load address details.");
            } finally {
                setLoading(false);
            }
        },
        [onError, onSelect],
    );

    return (
        <View testID="address-autocomplete">
            <TextInput
                value={query}
                onChangeText={setQuery}
                accessibilityLabel="Address"
                placeholder="Start typing your address"
                autoCapitalize="words"
                autoCorrect={false}
                testID="address-autocomplete-input"
                className="min-h-[44px] border border-border-light dark:border-border-dark rounded-lg px-3 font-open-sans-light text-foreground-light dark:text-foreground-dark"
            />
            {loading ? (
                <View className="mt-2">
                    <ActivityIndicator accessibilityLabel="Searching addresses" />
                </View>
            ) : null}
            {predictions.length > 0 ? (
                // @lat: [[mobile-address-autocomplete-design#Predictions list: no FlatList]]
                <View className="mt-2 border border-border-light dark:border-border-dark rounded-lg overflow-hidden">
                    {predictions.map((item) => (
                        <Pressable
                            key={item.placeID}
                            testID={`address-suggestion-${item.placeID}`}
                            onPress={() => void onPick(item.placeID, item.description)}
                            className="px-3 py-3 border-b border-border-light dark:border-border-dark"
                        >
                            <Text className="font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                {item.description}
                            </Text>
                        </Pressable>
                    ))}
                </View>
            ) : null}
        </View>
    );
}
