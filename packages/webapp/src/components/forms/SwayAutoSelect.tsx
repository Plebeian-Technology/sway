/** @format */

import { logDev } from "@sway/utils";
import { useField } from "formik";
import { isPlainObject } from "lodash";
import { useMemo } from "react";
import { Form } from "react-bootstrap";
import Select, { MultiValue, SingleValue } from "react-select";
import { sway } from "sway";
import { toSelectOption } from "../../utils";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | null) => void;
    handleSetTouched: (fieldname: string) => void;
    multiple?: boolean;
    style?: React.CSSProperties;
    helperText?: string;
    isKeepOpen?: boolean;
}

const SwayAutoSelect: React.FC<IProps> = ({
    field,
    error,
    setFieldValue,
    handleSetTouched,
    multiple,
    helperText,
}) => {
    const [formikField] = useField(field.name);

    const options = field.possibleValues as string[];
    logDev("SwayAutoSelect.options -", options);

    const value = useMemo(() => {
        if (formikField.value && typeof formikField.value === "string") {
            return [formikField.value];
        } else if (formikField.value && Array.isArray(formikField.value)) {
            return formikField.value;
        } else if (formikField.value && isPlainObject(formikField.value)) {
            return Object.keys(formikField.value);
        } else {
            return undefined;
        }
    }, [formikField.value]) as string[];

    if (!options) return null;

    if (!field.name.includes("organizations")) {
        logDev("SWAY AUTO SELECT VALUE", formikField?.value, value);
    }

    const isMulti = Boolean(multiple && multiple);

    return (
        <Form.Group controlId={field.name}>
            <Select
                className="w-100"
                id={field.name}
                isMulti={isMulti}
                value={
                    typeof value === "string" ? toSelectOption(value) : value.map(toSelectOption)
                }
                options={options.map(toSelectOption)}
                onChange={(values: SingleValue<sway.TOption> | MultiValue<sway.TOption>) => {
                    if (isMulti) {
                        setFieldValue(
                            field.name,
                            (values as MultiValue<sway.TOption>).map((v) => v.value),
                        );
                    } else {
                        setFieldValue(
                            field.name,
                            // eslint-disable-next-line
                            (values as SingleValue<sway.TOption>)?.value || "",
                        );
                    }
                    handleSetTouched(field.name);
                }}
                styles={{
                    control: (provided) => ({
                        ...provided,
                        cursor: "pointer",
                    }),
                    option: (provided) => ({
                        ...provided,
                        cursor: "pointer",
                    }),
                }}
            />
            {helperText && <div>{helperText}</div>}
            {error && <div className="danger">{helperText}</div>}
        </Form.Group>
    );
};

export default SwayAutoSelect;
