/** @format */

import { STATE_CODES_NAMES } from "src/constants";
import { get, logDev } from "src/utils";
import { FormikProps, FormikValues } from "formik";
import { useCallback } from "react";
import { sway } from "sway";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";

interface IProps {
    user: sway.IUser;
    fields: sway.IFormField[];
    formik: FormikProps<FormikValues>;
    isTextField: (field: sway.IFormField) => boolean;
}

const RegistrationFields: React.FC<IProps> = ({
    user,
    fields,
    formik,
    isTextField,
}) => {
    const { values, touched, errors, setFieldValue, setTouched } = formik;

    const handleSetTouched = useCallback((fieldname: string) => {
        if (touched[fieldname]) return;
        setTouched({
            ...touched,
            [fieldname]: true,
        });
    }, []);

    const errorMessage = useCallback((fieldname: string): string => {
        const _error = errors[fieldname] as string | undefined;
        if (touched[fieldname] && _error && !_error.includes("required")) {
            return _error;
        }
        return "";
    }, []);

    const handleSetFieldValue = useCallback(
        (
            field: string,
            value: string[] | string | null,
            shouldValidate?: boolean | undefined,
        ) => {
            if (typeof value === "string" && field === "regionCode") {
                setFieldValue(field, value, shouldValidate);
                setFieldValue(
                    "region",
                    STATE_CODES_NAMES[value],
                    shouldValidate,
                );
            } else {
                setFieldValue(field, value, shouldValidate);
            }
        },
        [],
    );

    const mappedRegistrationFields = fields.map((field: sway.IFormField) => {
        if (field.name === "country") return null;

        const currentUserFieldValue = get(user, field.name);

        if (!currentUserFieldValue && isTextField(field)) {
            return (
                <SwayText
                    key={field.name}
                    field={field}
                    value={values[field.name]}
                    error={errorMessage(field.name)}
                    setFieldValue={handleSetFieldValue}
                    handleSetTouched={handleSetTouched}
                />
            );
        }

        if (!currentUserFieldValue && field.component === "select") {
            return (
                <SwaySelect
                    key={field.name}
                    field={field}
                    value={values[field.name]}
                    error={errorMessage(field.name)}
                    setFieldValue={handleSetFieldValue}
                    handleSetTouched={handleSetTouched}
                />
            );
        }
        return null;
    });

    logDev("RegistrationFields - render mapped fields");
    return (
        <div className={"registration-fields-container"}>
            {mappedRegistrationFields}
        </div>
    );
};

export default RegistrationFields;
