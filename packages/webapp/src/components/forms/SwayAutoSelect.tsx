/** @format */

import { FormHelperText, TextField } from "@mui/material";
import Autocomplete from "@mui/material/Autocomplete";
import { logDev } from "@sway/utils";
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
    const [isOpen, setOpen] = useState<boolean>(false);
    const handleOpen = () => {
        setOpen(true);
    };
    const handleClose = () => {
        setOpen(false);
    };

    if (!field.possibleValues) return null;

    // TODO: Figure out where this is needed
    // const getValue = (params: sway.IPlainObject) => {
    //     if (params.inputProps.value) {
    //         return params.inputProps.value;
    //     }

    //     if (value) return value;
    //     if (field.default) return field.default;
    //     return value;
    // };

    return (
        <>
            <Autocomplete
                style={style && style}
                className="w-100"
                id={field.name}
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
                    logDev("OPEN");
                    handleOpen();
                }}
                onFocus={() => {
                    logDev("FOCUS");
                    handleOpen();
                }}
                onBlur={() => {
                    logDev("BLUR");
                    handleClose();
                }}
                onClose={() => {
                    logDev("CLOSE");
                    if (isKeepOpen) {
                        logDev("STOP CLOSE");
                    } else {
                        handleClose();
                    }
                }}
                onKeyDown={(e) => {
                    if (e.code === "Escape") {
                        handleClose();
                    }
                }}
                multiple={Boolean(multiple && multiple)}
                renderInput={(params) => {
                    return (
                        <TextField
                            {...params}
                            error={Boolean(error && error)}
                            inputProps={{
                                ...params.inputProps,
                                // value: getValue(params),
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
