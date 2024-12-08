/** @format */

import { useFormikContext } from "formik";
import { useCallback } from "react";
import { KeyOf, sway } from "sway";
import SwayText from "../forms/SwayText";
import AddressAutocomplete from "./AddressAutocomplete";

interface IProps<T> {
    user: sway.IUser;
    fields: sway.IFormField<T>[];
    isLoading: boolean;
    // setCoordinates: (coords: { lat: number | undefined; lng: number | undefined }) => void;
    setLoading: (l: boolean) => void;
}

const RegistrationFields = <T,>({ isLoading, setLoading, fields }: IProps<T>) => {
    const { values, touched, errors } = useFormikContext<sway.IUser>();

    const errorMessage = useCallback(
        (fieldname: keyof sway.IUser): string => {
            const error_ = errors[fieldname] as string | undefined;
            if (touched[fieldname] && error_ && !error_.includes("required")) {
                return error_;
            }
            return "";
        },
        [errors, touched],
    );

    const mappedRegistrationFields = fields.map((field: sway.IFormField<T>) => {
        if (field.name === "address") {
            return (
                <AddressAutocomplete
                    key={field.name}
                    field={field}
                    error={errorMessage(field.name as KeyOf<sway.IUser>)}
                    setLoading={setLoading}
                />
            );
        } else {
            return (
                <SwayText
                    key={field.name}
                    field={field}
                    value={values[field.name as keyof sway.IUser] as string}
                    error={errorMessage(field.name as keyof sway.IUser)}
                    disabled={isLoading}
                />
            );
        }
    });

    return <>{mappedRegistrationFields}</>;
};

export default RegistrationFields;
