/** @format */

import { Form } from "react-bootstrap";
import Select, { Options, SingleValue } from "react-select";
import { sway } from "sway";
import { toSelectOption } from "../../utils";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: React.CSSProperties;
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
    helperText,
    className,
}) => {
    if (!field.possibleValues) return null;

    return (
        <Form.Group controlId={field.name}>
            {field.label && <Form.Label>{field.label}</Form.Label>}
            <Select
                name={field.name}
                options={field.possibleValues as Options<{ label: string; value: string }>}
                value={toSelectOption(field.default || value)}
                onChange={(v: SingleValue<{ label: string; value: string }>) => {
                    setFieldValue(field.name, v?.value || "");
                    handleSetTouched(field.name);
                }}
                className={`w-100 ${className || ""}`}
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
            {field.subLabel && <span>{field.subLabel}</span>}
            {helperText && <span>{helperText}</span>}
            {error && <span className="danger">{error}</span>}
        </Form.Group>
    );
};

export default SwaySelect;
