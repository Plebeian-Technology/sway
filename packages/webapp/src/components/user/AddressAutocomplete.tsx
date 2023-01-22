import { isEmptyObject, logDev } from "@sway/utils";
import { useFormikContext } from "formik";
import { Form, ListGroup, Spinner } from "react-bootstrap";
import { sway } from "sway";
import usePlacesAutocomplete, { getGeocode, getLatLng, Suggestion } from "use-places-autocomplete";
import { handleError } from "../../utils";

interface IAddressComponent {
    long_name: string;
    short_name: string;
    types: string[];
}

interface IProps {
    field: sway.IFormField;
    error: string;
    disabled?: boolean;
    setCoordinates: (coords: { lat: number | undefined; lng: number | undefined }) => void;
    setLoading: (l: boolean) => void;
}

const AddressAutocomplete: React.FC<IProps> = ({
    disabled,
    field,
    error,
    setCoordinates,
    setLoading,
}) => {
    const { setFieldValue } = useFormikContext<sway.IUser>();

    const {
        value,
        suggestions: { status, data, loading },
        setValue,
        clearSuggestions,
    } = usePlacesAutocomplete({
        debounce: 300,
    });

    const handleInput = (e: React.ChangeEvent<HTMLInputElement>) => {
        setValue(e.target.value);
    };

    const handleSelect = (suggestion: Suggestion) => () => {
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
                if (!isEmptyObject(results)) {
                    const { lat, lng } = getLatLng(results.first());
                    logDev("RegistrationFields.getLatLng - RESULTS -", { lat, lng });
                    setCoordinates({ lat, lng });
                }

                const components = results.first().address_components as IAddressComponent[];
                const streetNumber = components.find((c) =>
                    c.types.includes("street_number"),
                )?.long_name;
                const street = components.find((c) => c.types.includes("route"))?.long_name;
                if (streetNumber && street) {
                    setFieldValue("address1", `${streetNumber} ${street}`);
                }

                // const address2 = components.find((c) => c.types.includes("street_number"))?.long_name;

                const city = components.find((c) => c.types.includes("locality"))?.long_name;
                if (city) {
                    setFieldValue("city", city);
                }

                const region = components.find((c) =>
                    c.types.includes("administrative_area_level_1"),
                )?.long_name;
                if (region) {
                    setFieldValue("region", region);
                }

                const regionCode = components.find((c) =>
                    c.types.includes("administrative_area_level_1"),
                )?.short_name;
                if (regionCode) {
                    setFieldValue("regionCode", regionCode);
                }

                const postalCode = components.find((c) =>
                    c.types.includes("postal_code"),
                )?.long_name;
                if (postalCode) {
                    setFieldValue("postalCode", postalCode);
                }

                const postalCodeExtension = components.find((c) =>
                    c.types.includes("postal_code_suffix"),
                )?.long_name;
                if (postalCodeExtension) {
                    setFieldValue("postalCodeExtension", postalCodeExtension);
                }

                const country = components.find((c) => c.types.includes("country"))?.long_name;
                if (country) {
                    setFieldValue("country", country);
                }
            })
            .catch((e) => {
                setLoading(false);
                handleError(e);
            });
    };

    const renderSuggestions = () => {
        return (
            <ListGroup className="mt-1">
                {data.map((suggestion) => {
                    const {
                        place_id,
                        structured_formatting: { main_text, secondary_text },
                    } = suggestion;

                    return (
                        <ListGroup.Item key={place_id} onClick={handleSelect(suggestion)}>
                            <strong>{main_text}</strong> <small>{secondary_text}</small>
                        </ListGroup.Item>
                    );
                })}
            </ListGroup>
        );
    };

    return (
        <Form.Group controlId={field.name}>
            <Form.Label className="mt-2">
                {field.label} {loading && <Spinner animation="border" size="sm" />}
            </Form.Label>
            <Form.Control
                key={field.name}
                name={field.name}
                autoComplete="off"
                value={value}
                onChange={handleInput}
                required={field.isRequired}
                isInvalid={!!error}
                disabled={field.disabled || !!disabled}
            />
            {status === "OK" && renderSuggestions()}
        </Form.Group>
    );
};

export default AddressAutocomplete;
