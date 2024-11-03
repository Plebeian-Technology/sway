import { useJsApiLoader } from "@react-google-maps/api";
import { useFormikContext } from "formik";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import { Form, ListGroup, ProgressBar } from "react-bootstrap";
import { sway } from "sway";
import usePlacesAutocomplete, { Suggestion, getGeocode, getLatLng } from "use-places-autocomplete";
import { handleError, logDev } from "../../sway_utils";

interface IAddressComponent {
    long_name: string;
    short_name: string;
    types: string[];
}

interface IProps {
    field: sway.IFormField;
    error: string;
    setLoading: (l: boolean) => void;
}

const GOOGLE_MAPS_LIBRARIES = ["places"] as ["places"];

const Autocomplete: React.FC<IProps> = ({ field, error, setLoading }) => {
    const { values, setFieldValue } = useFormikContext<sway.IAddress>();

    const defaultValue = useMemo(
        () => (isEmpty(values) ? "" : `${values.street} ${values.city}, ${values.regionCode}, ${values.postalCode}`),
        [values],
    );

    // https://github.com/wellyshen/use-places-autocomplete#lazily-initializing-the-hook
    const {
        value,
        setValue,
        suggestions: { status, data, loading },
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
                        // setCoordinates({ lat, lng });
                        setFieldValue("latitude", lat).catch(console.error);
                        setFieldValue("longitude", lng).catch(console.error);
                    }

                    const components = results.first().address_components as IAddressComponent[];
                    const streetNumber = components.find((c) => c.types.includes("street_number"))?.long_name;
                    const street = components.find((c) => c.types.includes("route"))?.long_name;
                    if (streetNumber && street) {
                        setFieldValue("street", `${streetNumber} ${street}`).catch(console.error);
                    }

                    // const address2 = components.find((c) => c.types.includes("street_number"))?.long_name;

                    const city = components.find((c) => c.types.includes("locality"))?.long_name;
                    if (city) {
                        setFieldValue("city", city).catch(console.error);
                    }

                    const region = components.find((c) => c.types.includes("administrative_area_level_1"))?.long_name;
                    if (region) {
                        setFieldValue("region", region).catch(console.error);
                    }

                    const regionCode = components.find((c) =>
                        c.types.includes("administrative_area_level_1"),
                    )?.short_name;
                    if (regionCode) {
                        setFieldValue("regionCode", regionCode).catch(console.error);
                    }

                    const postalCode = components.find((c) => c.types.includes("postal_code"))?.long_name;
                    if (postalCode) {
                        setFieldValue("postalCode", postalCode).catch(console.error);
                    }

                    const postalCodeExtension = components.find((c) =>
                        c.types.includes("postal_code_suffix"),
                    )?.long_name;
                    if (postalCodeExtension) {
                        setFieldValue("postalCodeExtension", postalCodeExtension).catch(console.error);
                    }

                    const country = components.find((c) => c.types.includes("country"))?.long_name;
                    if (country) {
                        setFieldValue("country", country).catch(console.error);
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                })
                .finally(() => {
                    setLoading(false);
                });
        },
        [clearSuggestions, setFieldValue, setLoading, setValue],
    );

    const renderSuggestions = useCallback(() => {
        return (
            <ListGroup className="mt-1">
                {data.map((suggestion) => {
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
    }, [data, handleSelect]);

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
                    isInvalid={!!error}
                    disabled={field.disabled || loading}
                    placeholder={field.label}
                />
            </Form.FloatingLabel>
            {status === "OK" && renderSuggestions()}
        </Form.Group>
    );
};

const AddressAutocomplete: React.FC<IProps> = (props) => {
    logDev("AddressAutocomplete.googleMapsApiKey -", import.meta.env.VITE_GOOGLE_MAPS_API_KEY);
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
