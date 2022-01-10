/** @format */

import { FormHelperText, TextareaAutosize, Typography } from "@mui/material";
import { Field } from "formik";
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
    value,
}) => {
    const handleChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
        setFieldValue(field.name, event?.target?.value);
        handleSetTouched(field.name);
    };

    const wordCount = value?.match(/\s/g)?.length || 0;

    return (
        <>
            <Field
                label={field.label}
                onChange={handleChange}
                required={field.isRequired}
                variant={"outlined"}
                component={TextareaAutosize}
                multiline={"true"}
                minRows={rows || 5}
                type={field.type}
                name={field.name}
                className="w-100 p-2"
                value={value}
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
