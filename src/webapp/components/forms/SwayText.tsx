/** @format */

import { FormHelperText, TextField, Typography } from "@mui/material";
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
}

const SwayText: React.FC<IProps> = ({
    field,
    value,
    error,
    setFieldValue,
    handleSetTouched,
    style,
    helperText,
}) => {
    const gen = field.component === "generatedText";

    return (
        <>
            {gen ? (
                <Field
                    component={TextField}
                    type={field.type}
                    label={field.label}
                    InputLabelProps={
                        style && style.inputLabel && { ...style.inputLabel }
                    }
                    InputProps={style && style.input}
                    error={Boolean(error)}
                    required={field.isRequired}
                    variant={"outlined"}
                    name={field.name}
                    disabled={true}
                    value={field.default || value}
                    style={style && style}
                    autoComplete={field.autoComplete}
                    className="w-100"
                />
            ) : (
                <>
                    <Field
                        component={TextField}
                        type={field.type}
                        label={field.label}
                        InputLabelProps={
                            style && style.inputLabel && { ...style.inputLabel }
                        }
                        InputProps={style && style.input}
                        error={Boolean(error)}
                        required={field.isRequired}
                        variant={"outlined"}
                        name={field.name}
                        disabled={field.disabled || false}
                        value={field.default || value}
                        onChange={(
                            event: React.ChangeEvent<HTMLInputElement>,
                        ) => {
                            setFieldValue(field.name, event?.target?.value);
                            handleSetTouched(field.name);
                        }}
                        style={style && style}
                        autoComplete={field.autoComplete}
                        className="w-100"
                    />
                    {field.subLabel && (
                        <Typography component={"span"} variant={"body2"}>
                            {field.subLabel}
                        </Typography>
                    )}
                </>
            )}
            <FormHelperText>{helperText || ""}</FormHelperText>
        </>
    );
};

export default SwayText;