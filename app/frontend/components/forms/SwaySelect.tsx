/** @format */

import { Form } from "react-bootstrap";
import Select, { SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";
import { REACT_SELECT_STYLES, toSelectOption } from "../../sway_utils";

interface IProps<T> {
    field: sway.IFormField<T>;
    value: ISelectOption;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    handleSetTouched: (fieldname: string) => void;
    style?: React.CSSProperties;
    containerStyle?: React.CSSProperties;
    helperText?: string;
    isKeepOpen?: boolean;
    className?: string;
}

const SwaySelect = <T,>({ field, value, error, setFieldValue, handleSetTouched, helperText, className }: IProps<T>) => {
    if (!field.possibleValues) return null;

    return (
        <Form.Group controlId={field.name}>
            {field.label && (
                <Form.Label className="bold">
                    {field.label}
                    {field.isRequired ? " *" : " (Optional)"}
                </Form.Label>
            )}
            <Select
                name={field.name}
                options={field.possibleValues as ISelectOption[]}
                value={value || toSelectOption(field.default || "Select...", field.default || "")}
                onChange={(v: SingleValue<ISelectOption>) => {
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
