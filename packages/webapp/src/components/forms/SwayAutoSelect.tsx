/** @format */

import { TextField } from "@material-ui/core";
import { Autocomplete, AutocompleteRenderInputParams } from "@material-ui/lab";
import { sway } from "sway";
import React from "react";

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
}

const SwayAutoSelect: React.FC<IProps> = ({
    field,
    // value,
    error,
    setFieldValue,
    handleSetTouched,
    multiple,
    style,
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
                    event: React.ChangeEvent<Record<string, unknown>>,
                    newValue: string[] | string | null,
                ) => {
                    setFieldValue(field.name, newValue);
                    handleSetTouched(field.name);
                }}
                multiple={Boolean(multiple && multiple)}
                renderInput={(params: AutocompleteRenderInputParams) => {
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
        </SwayBase>
    );
};

export default SwayAutoSelect;
