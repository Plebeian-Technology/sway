/** @format */

import { FormHelperText, TextField } from "@mui/material";
import Autocomplete from "@mui/material/Autocomplete";
import React from "react";
import { sway } from "sway";
import SwayBase from "./SwayBase";

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
}) => {
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
        <SwayBase>
            <Autocomplete
                style={style && style}
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
        </SwayBase>
    );
};

export default SwayAutoSelect;
