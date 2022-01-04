/** @format */

import { FormHelperText, TextField, Typography } from "@mui/material";
import { Field } from "formik";
import React, { useState } from "react";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: sway.IPlainObject;
    helperText?: string;
    rows?: number;
}

const SwayTextArea: React.FC<IProps> = ({
    field,
    error,
    setFieldValue,
    handleSetTouched,
    helperText,
    rows,
}) => {
    const [wordCount, setWordCount] = useState<number>(0);

    const handleChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
        const value = event?.target?.value;
        setFieldValue(field.name, value);
        handleSetTouched(field.name);

        const count = value.split(" ").length - 1;
        setWordCount(count);
    };

    return (
        <>
            <Field
                label={field.label}
                onChange={handleChange}
                required={field.isRequired}
                variant={"outlined"}
                component={TextField}
                multiline={true}
                rows={rows || 10}
                type={field.type}
                name={field.name}
                className="w-100"
            />
            <FormHelperText>
                {`${helperText} | Word Count - ${wordCount}` ||
                    `Word Count - ${wordCount}`}
            </FormHelperText>
            <Typography>{error && error}</Typography>
        </>
    );
};

export default SwayTextArea;
