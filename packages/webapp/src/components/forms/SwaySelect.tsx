/** @format */

import { FormHelperText, MenuItem, Typography } from "@mui/material";
import Select, { SelectChangeEvent } from "@mui/material/Select";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: sway.IPlainObject;
    containerStyle?: sway.IPlainObject;
    helperText?: string;
    isKeepOpen?: boolean;
    className?: string;
}

const SwaySelect: React.FC<IProps> = ({
    field,
    value,
    error,
    setFieldValue,
    handleSetTouched,
    style,
    helperText,
    className,
}) => {
    if (!field.possibleValues) return null;

    const getChildren = () => {
        if (!field.possibleValues) return [];

        if (typeof field.possibleValues[0] === "string") {
            return (field.possibleValues as string[]).map((option: string, index: number) => (
                <MenuItem key={option + index} value={option}>
                    {option}
                </MenuItem>
            ));
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
        <>
            <Select
                label={field.label}
                inputProps={style && style.input}
                error={Boolean(error && error)}
                required={field.isRequired}
                variant={"outlined"}
                name={field.name}
                disabled={field.disabled || false}
                value={field.default || value}
                onChange={(event: SelectChangeEvent<string>) => {
                    setFieldValue(field.name, event?.target?.value);
                    handleSetTouched(field.name);
                }}
                style={style && style}
                autoComplete={field.autoComplete}
                className={`w-100 ${className || ""}`}
            >
                {children}
            </Select>
            {field.subLabel && (
                <Typography component={"span"} variant={"body2"}>
                    {field.subLabel}
                </Typography>
            )}
            <FormHelperText>{helperText || ""}</FormHelperText>
        </>
    );
};

export default SwaySelect;
