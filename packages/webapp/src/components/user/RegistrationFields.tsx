/** @format */

import { useFormikContext } from "formik";
import { useCallback } from "react";
import { sway } from "sway";
import SwayText from "../forms/SwayText";
import AddressAutocomplete from "./AddressAutocomplete";

interface IProps {
    user: sway.IUser;
    fields: sway.IFormField[];
    setCoordinates: (coords: { lat: number | undefined; lng: number | undefined }) => void;
}

const RegistrationFields: React.FC<IProps> = ({ fields, setCoordinates }) => {
    const { values, touched, errors } = useFormikContext<sway.IUser>();

    const errorMessage = useCallback((fieldname: string): string => {
        const _error = errors[fieldname] as string | undefined;
        if (touched[fieldname] && _error && !_error.includes("required")) {
            return _error;
        }
        return "";
    }, []);

    const mappedRegistrationFields = fields.map((field: sway.IFormField) => {
        if (field.name === "address") {
            return (
                <AddressAutocomplete
                    key={field.name}
                    field={field}
                    error={errorMessage(field.name)}
                    setCoordinates={setCoordinates}
                />
            );
        } else {
            return (
                <SwayText
                    key={field.name}
                    field={field}
                    value={values[field.name]}
                    error={errorMessage(field.name)}
                />
            );
        }
    });

    return <>{mappedRegistrationFields}</>;
};

export default RegistrationFields;
