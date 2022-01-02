/** @format */

import { FormHelperText, MenuItem, TextField, Typography } from "@mui/material";
import React from "react";
import { sway } from "sway";
import SwayBase from "./SwayBase";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: sway.IPlainObject;
    containerStyle?: sway.IPlainObject;
    helperText?: string;
}

const SwaySelect: React.FC<IProps> = ({
    field,
    value,
    error,
    setFieldValue,
    handleSetTouched,
    style,
    containerStyle,
    helperText,
}) => {
    if (!field.possibleValues) return null;

    const getChildren = () => {
        if (!field.possibleValues) return [];

        if (typeof field.possibleValues[0] === "string") {
            return (field.possibleValues as string[]).map(
                (option: string, index: number) => (
                    <MenuItem key={option + index} value={option}>
                        {option}
                    </MenuItem>
                ),
            );
        }
        return (field.possibleValues as { label: string; value: string }[]).map(
            (option: { label: string; value: string }, index: number) => (
                <MenuItem key={option.value + index} value={option.value}>
                    {option.label}
                </MenuItem>
            ),
        );
    };

    const children = getChildren();

    return (
        <SwayBase key={field.name} style={containerStyle && containerStyle}>
            <TextField
                select
                type={"select"}
                label={field.label}
                InputLabelProps={style && style.inputlabel}
                InputProps={style && style.input}
                error={Boolean(error && error)}
                required={field.isRequired}
                variant={"outlined"}
                name={field.name}
                disabled={field.disabled || false}
                value={field.default || value}
                onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                    setFieldValue(field.name, event?.target?.value);
                    handleSetTouched(field.name);
                }}
                style={style && style}
                autoComplete={field.autoComplete}
            >
                {children}
            </TextField>
            {field.subLabel && (
                <Typography component={"span"} variant={"body2"}>
                    {field.subLabel}
                </Typography>
            )}
            <FormHelperText>{helperText || ""}</FormHelperText>
        </SwayBase>
    );
};

export default SwaySelect;
