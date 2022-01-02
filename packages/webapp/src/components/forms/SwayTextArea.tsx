/** @format */

import { FormHelperText, TextField, Typography } from "@mui/material";
import { Field } from "formik";
import { sway } from "sway";
import React from "react";

import SwayBase from "./SwayBase";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: sway.IPlainObject;
    helperText?: string;
}

const SwayTextArea: React.FC<IProps> = ({
    field,
    error,
    setFieldValue,
    handleSetTouched,
    style,
    helperText,
}) => {
    return (
        <SwayBase style={style}>
            <Field
                label={field.label}
                onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                    setFieldValue(field.name, event?.target?.value);
                    handleSetTouched(field.name);
                }}
                required={field.isRequired}
                variant={"outlined"}
                component={TextField}
                multiline={true}
                rows={10}
                type={field.type}
                name={field.name}
            />
            <FormHelperText>{helperText || ""}</FormHelperText>
            <Typography>{error && error}</Typography>
        </SwayBase>
    );
};

export default SwayTextArea;
