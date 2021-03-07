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
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | null) => void;
    handleSetTouched: (fieldname: string) => void
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

    return (
        <SwayBase key={field.name}>
            <Autocomplete
                style={style && style}
                id={field.name}
                disabled={field.disabled}
                options={field.possibleValues as string[]}
                getOptionLabel={(option: string) => option}
                onChange={(event: React.ChangeEvent<Record<string, unknown>>, newValue: string[] | string | null) => {
                    setFieldValue(field.name, newValue);
                    handleSetTouched(field.name);
                }}
                defaultValue={field.default}
                multiple={Boolean(multiple && multiple)}
                autoComplete={!!field.autoComplete}
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
                            autoComplete={field.autoComplete}
                        />
                    );
                }}
            />
        </SwayBase>
    );
};

export default SwayAutoSelect;
