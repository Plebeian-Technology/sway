/** @format */

import { useFormikContext } from "formik";
import { useCallback } from "react";
import { sway } from "sway";
import SwayText from "../forms/SwayText";
import AddressAutocomplete from "./AddressAutocomplete";

interface IProps {
    user: sway.IUser;
    fields: sway.IFormField[];
    isLoading: boolean;
    setCoordinates: (coords: { lat: number | undefined; lng: number | undefined }) => void;
    setLoading: (l: boolean) => void;
}

const RegistrationFields: React.FC<IProps> = ({
    isLoading,
    setLoading,
    fields,
    setCoordinates,
}) => {
    const { values, touched, errors } = useFormikContext<sway.IUser>();

    const errorMessage = useCallback(
        (fieldname: string): string => {
            const _error = errors[fieldname] as string | undefined;
            if (touched[fieldname] && _error && !_error.includes("required")) {
                return _error;
            }
            return "";
        },
        [errors, touched],
    );

    const mappedRegistrationFields = fields.map((field: sway.IFormField) => {
        if (field.name === "address") {
            return (
                <AddressAutocomplete
                    disabled={isLoading}
                    key={field.name}
                    field={field}
                    error={errorMessage(field.name)}
                    setCoordinates={setCoordinates}
                    setLoading={setLoading}
                />
            );
        } else {
            return (
                <SwayText
                    key={field.name}
                    field={field}
                    value={values[field.name]}
                    error={errorMessage(field.name)}
                    disabled={isLoading}
                />
            );
        }
    });

    return <>{mappedRegistrationFields}</>;
};

export default RegistrationFields;
