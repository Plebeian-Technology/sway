import { useJsApiLoader } from "@react-google-maps/api";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import { Form, ListGroup, ProgressBar } from "react-bootstrap";
import { sway } from "sway";
import usePlacesAutocomplete, { Suggestion, getGeocode, getLatLng } from "use-places-autocomplete";
import { logDev } from "../../sway_utils";

interface IAddressComponent {
    long_name: string;
    short_name: string;
    types: string[];
}

interface IProps<T> {
    field: sway.IFormField<T>;
    setLoading: (l: boolean) => void;
}

const GOOGLE_MAPS_LIBRARIES = ["places"] as ["places"];

const Autocomplete = <T,>({ field, setLoading }: IProps<T>) => {
    const { data, setData, errors } = useFormContext<sway.IAddress>();

    const defaultValue = useMemo(
        () => (isEmpty(data) ? "" : `${data.street} ${data.city}, ${data.region_code}, ${data.postal_code}`),
        [data],
    );

    // https://github.com/wellyshen/use-places-autocomplete#lazily-initializing-the-hook
    const {
        value,
        setValue,
        suggestions: { status, data: autoCompleteData, loading },
        clearSuggestions,
    } = usePlacesAutocomplete({
        debounce: 1000,
        initOnMount: true,
        defaultValue,
    });

    const handleInput = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            setValue(e.target.value);
        },
        [setValue],
    );

    const handleSelect = useCallback(
        (suggestion: Suggestion) => () => {
            setLoading(true);
            logDev("RegistrationFields.handleSelect - SELECTED ADDRESS -", suggestion);

            // When user selects a place, we can replace the keyword without request data from API
            // by setting the second parameter to "false"
            setValue(suggestion.description, false);
            clearSuggestions();

            // Get latitude and longitude via utility functions
            getGeocode({ address: suggestion.description })
                .then((results) => {
                    setLoading(false);
                    logDev("RegistrationFields.getGeocode - RESULTS -", results);
                    if (!isEmpty(results)) {
                        const { lat, lng } = getLatLng(results.first());
                        logDev("RegistrationFields.getLatLng - RESULTS -", { lat, lng });
                        setData("latitude", lat);
                        setData("longitude", lng);
                    }

                    const components = results.first().address_components as IAddressComponent[];
                    const streetNumber = components.find((c) => c.types.includes("street_number"))?.long_name;
                    const street = components.find((c) => c.types.includes("route"))?.long_name;
                    if (streetNumber && street) {
                        setData("street", `${streetNumber} ${street}`);
                    }

                    // const address2 = components.find((c) => c.types.includes("street_number"))?.long_name;

                    const city = components.find((c) => c.types.includes("locality"))?.long_name;
                    if (city) {
                        setData("city", city);
                    }

                    const region = components.find((c) => c.types.includes("administrative_area_level_1"))?.long_name;
                    if (region) {
                        setData("region", region);
                    }

                    const region_code = components.find((c) =>
                        c.types.includes("administrative_area_level_1"),
                    )?.short_name;
                    if (region_code) {
                        setData("region_code", region_code);
                    }

                    const postal_code = components.find((c) => c.types.includes("postal_code"))?.long_name;
                    if (postal_code) {
                        setData("postal_code", postal_code);
                    }

                    const country = components.find((c) => c.types.includes("country"))?.long_name;
                    if (country) {
                        setData("country", country);
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    console.error(e);
                })
                .finally(() => {
                    setLoading(false);
                });
        },
        [clearSuggestions, setData, setLoading, setValue],
    );

    const renderSuggestions = useCallback(() => {
        return (
            <ListGroup className="mt-1">
                {autoCompleteData.map((suggestion) => {
                    const {
                        place_id,
                        structured_formatting: { main_text, secondary_text },
                    } = suggestion;

                    return (
                        <ListGroup.Item key={place_id} onClick={handleSelect(suggestion)} className="text-start">
                            <strong>{main_text}</strong> <small>{secondary_text}</small>
                        </ListGroup.Item>
                    );
                })}
            </ListGroup>
        );
    }, [autoCompleteData, handleSelect]);

    return (
        <Form.Group controlId={field.name}>
            <Form.FloatingLabel className="mt-2" label={field.label}>
                <Form.Control
                    key={field.name}
                    name={field.name}
                    autoComplete="off"
                    value={value}
                    onChange={handleInput}
                    required={field.isRequired}
                    isInvalid={!isEmpty(errors)}
                    disabled={field.disabled || loading}
                    placeholder={field.label}
                />
            </Form.FloatingLabel>
            {status === "OK" && renderSuggestions()}
        </Form.Group>
    );
};

const AddressAutocomplete = <T,>(props: IProps<T>) => {
    const { isLoaded } = useJsApiLoader({
        googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string,
        libraries: GOOGLE_MAPS_LIBRARIES,
        preventGoogleFontsLoading: true,
    });

    if (isLoaded) {
        return <Autocomplete {...props} />;
    } else {
        return <ProgressBar animated now={100} />;
    }
};

export default AddressAutocomplete;
