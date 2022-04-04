/** @format */

import { FormHelperText, TextField } from "@mui/material";
import Autocomplete from "@mui/material/Autocomplete";
import { logDev } from "@sway/utils";
import { useField } from "formik";
import { isPlainObject } from "lodash";
import { useMemo, useState } from "react";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (
        fieldname: string,
        fieldvalue: string[] | string | null,
    ) => void;
    handleSetTouched: (fieldname: string) => void;
    multiple?: boolean;
    style?: sway.IPlainObject;
    helperText?: string;
    isKeepOpen?: boolean;
}

const SwayAutoSelect: React.FC<IProps> = ({
    field,
    // value,
    error,
    setFieldValue,
    handleSetTouched,
    multiple,
    style,
    helperText,
    isKeepOpen,
}) => {
    const [formikField] = useField(field.name);
    const [isOpen, setOpen] = useState<boolean>(false);

    const handleOpen = () => {
        setOpen(true);
    };
    const handleClose = () => {
        setOpen(false);
    };

    const possibleValues = field.possibleValues as string[];
    if (!possibleValues) return null;

    const value = useMemo(() => {
        if (formikField.value && Array.isArray(formikField.value)) {
            return formikField.value;
        } else if (formikField.value && isPlainObject(formikField.value)) {
            return Object.keys(formikField.value);
        } else {
            return [];
        }
    }, [formikField.value]) as string[];

    if (!field.name.includes("organizations")) {
        logDev("SWAY AUTO SELECT VALUE", value);
    }

    return (
        <>
            <Autocomplete
                style={style && style}
                className="w-100"
                id={field.name}
                multiple={Boolean(multiple && multiple)}
                value={value}
                disabled={field.disabled}
                options={possibleValues}
                getOptionLabel={(o: string) => o}
                onChange={(
                    event: React.ChangeEvent<any>,
                    newValue: string[] | string | null,
                    reason,
                    details,
                ) => {
                    event.preventDefault();
                    event.stopPropagation();

                    const _newValue = newValue as string[];
                    const selectedOption = details?.option;
                    logDev(
                        "SwayAutoSelect.onChange - NEW VALUE -",
                        field.name,
                        _newValue,
                        selectedOption,
                    );
                    setFieldValue(field.name, selectedOption || null);
                    handleSetTouched(field.name);
                }}
                open={isOpen}
                onOpen={() => {
                    logDev("SwayAutoSelect - OPEN");
                    handleOpen();
                }}
                onFocus={() => {
                    logDev("SwayAutoSelect - FOCUS");
                    handleOpen();
                }}
                onBlur={() => {
                    logDev("SwayAutoSelect - BLUR");
                    handleClose();
                }}
                onClose={() => {
                    logDev("SwayAutoSelect - CLOSE");
                    if (isKeepOpen) {
                        logDev("SwayAutoSelect - STOP CLOSE");
                    } else {
                        handleClose();
                    }
                }}
                onKeyDown={(e) => {
                    if (e.code === "Escape") {
                        logDev("SwayAutoSelect - KEYDOWN CLOSE");
                        handleClose();
                    }
                }}
                renderInput={(params) => {
                    return (
                        <TextField
                            {...params}
                            error={Boolean(error && error)}
                            inputProps={{
                                ...params.inputProps,
                            }}
                            label={field.label}
                            name={field.name}
                            required={field.isRequired}
                            variant={"outlined"}
                        />
                    );
                }}
            />
            <FormHelperText>{helperText || ""}</FormHelperText>
        </>
    );
};

export default SwayAutoSelect;
