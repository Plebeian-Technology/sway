/** @format */

import {
    BALTIMORE_COUNTY_LOCALE_NAME,
    CONGRESS_LOCALE_NAME,
    STATE_CODES_NAMES,
} from "@sway/constants";
import {
    fromLocaleNameItem,
    get,
    LOCALES_WITHOUT_CONGRESS,
    LOCALE_NOT_LISTED_LABEL,
    logDev,
    SELECT_LOCALE_LABEL,
    toFormattedLocaleName,
} from "@sway/utils";
import { FormikProps, FormikValues } from "formik";
import React, { useCallback, useMemo } from "react";
import { sway } from "sway";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";
import LocaleSelector from "./LocaleSelector";
import { ADDRESS_FIELDS } from "./Registration";

interface IProps {
    user: sway.IUser;
    fields: sway.IFormField[];
    formik: FormikProps<FormikValues>;
    isLocaleField: (field: sway.IFormField) => boolean;
    isLocaleSelected: (selectedLocale: sway.ILocale) => boolean;
    isLocaleASuperLocale: (selectedLocale: sway.ILocale) => boolean;
    isAutofillLocaleField: (
        field: sway.IFormField,
        selectedLocale: sway.ILocale,
    ) => boolean;
    isTextField: (field: sway.IFormField) => boolean;
}

const RegistrationFields: React.FC<IProps> = ({
    user,
    fields,
    formik,
    isLocaleField,
    isLocaleSelected,
    isLocaleASuperLocale,
    isAutofillLocaleField,
    isTextField,
}) => {
    const { values, touched, errors, setFieldValue, setTouched } = formik;

    const possibleLocales = useMemo(
        () => [
            {
                name: SELECT_LOCALE_LABEL,
            } as sway.ILocale,
            ...LOCALES_WITHOUT_CONGRESS,
            {
                name: LOCALE_NOT_LISTED_LABEL,
            } as sway.ILocale,
        ],
        [],
    );

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

    const renderLocaleAutofillFields = useCallback(
        (vals: FormikValues, field: sway.IFormField) => {
            if (
                field.name === "city" &&
                isLocaleASuperLocale(vals.selectedLocale)
            ) {
                return (
                    <SwayText
                        key={field.name}
                        field={field}
                        value={vals[field.name]}
                        error={errorMessage(field.name)}
                        setFieldValue={handleSetFieldValue}
                        handleSetTouched={handleSetTouched}
                    />
                );
            }
            const val = get(vals, `selectedLocale.${field.name}`);
            if (!val) return null;
            return (
                <SwayText
                    key={field.name}
                    field={{
                        ...field,
                        disabled: true,
                    }}
                    value={
                        field.name === "city" ? toFormattedLocaleName(val) : val
                    }
                    error={""}
                    setFieldValue={() => null}
                    handleSetTouched={() => null}
                />
            );
        },
        [],
    );

    const handleSelectLocale = useCallback((locale: sway.ILocale) => {
        setFieldValue("selectedLocale", locale);
        if (
            [
                CONGRESS_LOCALE_NAME,
                SELECT_LOCALE_LABEL,
                LOCALE_NOT_LISTED_LABEL,
            ].includes(locale.name)
        ) {
            return;
        }
        ADDRESS_FIELDS.forEach((f) => setFieldValue(f, ""));
        setFieldValue("region", fromLocaleNameItem(locale.region));
        setFieldValue("regionCode", locale.regionCode.toUpperCase());
        if (locale.name !== BALTIMORE_COUNTY_LOCALE_NAME) {
            setFieldValue("city", fromLocaleNameItem(locale.city));
        } else {
            setFieldValue("city", "");
        }
    }, []);

    const mappedRegistrationFields = fields.map((field: sway.IFormField) => {
        if (field.name === "country") return null;

        if (field.name === "selectedLocale") {
            return (
                <LocaleSelector
                    key={field.name}
                    locales={possibleLocales}
                    locale={values[field.name]}
                    setLocale={handleSelectLocale}
                />
            );
        }

        if (!isLocaleSelected(values.selectedLocale) && isLocaleField(field)) {
            return null;
        }

        if (
            isLocaleSelected(values.selectedLocale) &&
            isAutofillLocaleField(field, values.selectedLocale)
        ) {
            return renderLocaleAutofillFields(values, field);
        }

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
