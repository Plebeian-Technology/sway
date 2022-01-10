/** @format */

import { FormHelperText, TextField } from "@mui/material";
import Autocomplete from "@mui/material/Autocomplete";
import { logDev } from "@sway/utils";
import { useField } from "formik";
import React, { useState } from "react";
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

    if (!field.possibleValues) return null;

    return (
        <>
            <Autocomplete
                style={style && style}
                className="w-100"
                id={field.name}
                multiple={Boolean(multiple && multiple)}
                value={formikField.value}
                disabled={field.disabled}
                options={field.possibleValues as string[]}
                getOptionLabel={(option: string) => option}
                onChange={(
                    event: React.ChangeEvent<any>,
                    newValue: string[] | string | null,
                ) => {
                    setFieldValue(field.name, newValue);
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
