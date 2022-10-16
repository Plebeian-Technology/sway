/** @format */

import { Form } from "react-bootstrap";
import Select, { Options, SingleValue } from "react-select";
import { sway } from "sway";
import { REACT_SELECT_STYLES, toSelectOption } from "../../utils";

interface IProps {
    field: sway.IFormField;
    value: sway.TOption;
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
            {field.label && (
                <Form.Label>
                    {field.label}
                    {field.isRequired ? " *" : " (Optional)"}
                </Form.Label>
            )}
            <Select
                name={field.name}
                options={field.possibleValues as Options<sway.TOption>}
                value={value || toSelectOption(field.default || "Select...", field.default || "")}
                onChange={(v: SingleValue<sway.TOption>) => {
                    setFieldValue(field.name, (v?.value as string) || "");
                    handleSetTouched(field.name);
                }}
                menuPosition="fixed"
                className={`w-100 ${className || ""}`}
                styles={REACT_SELECT_STYLES}
            />
            {field.subLabel && <div>{field.subLabel}</div>}
            {helperText && <div className="text-muted">{helperText}</div>}
            <div className="text-danger">{error}</div>
        </Form.Group>
    );
};

export default SwaySelect;
