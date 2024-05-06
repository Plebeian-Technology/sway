/** @format */

import { Field } from "formik";
import { useCallback } from "react";
import ReactTextareaAutosize from "react-textarea-autosize";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: React.CSSProperties;
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
    const handleChange = useCallback(
        async (event: React.ChangeEvent<HTMLInputElement>) => {
            setFieldValue(field.name, event?.target?.value);
            handleSetTouched(field.name);
        },
        [setFieldValue, handleSetTouched, field.name],
    );

    const wordCount = value?.match(/\s/g)?.length || 0;

    return (
        <>
            <Field
                label={field.label}
                onChange={handleChange}
                required={field.isRequired}
                variant={"outlined"}
                component={ReactTextareaAutosize}
                multiline={"true"}
                minRows={rows || 5}
                type={field.type}
                name={field.name}
                className="w-100 p-2"
                value={value}
            />
            <div className="text-muted">
                {`${helperText} | Word Count - ${wordCount}` || `Word Count - ${wordCount}`}
            </div>
            <div className="text-danger">{error && error}</div>
        </>
    );
};

export default SwayTextArea;
