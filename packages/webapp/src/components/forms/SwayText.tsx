/** @format */

import { useCallback } from "react";
import { Form } from "react-bootstrap";
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
    const isGeneratedText = field.component === "generatedText";

    const handleChange = useCallback(
        (event: React.ChangeEvent<HTMLInputElement>) => {
            setFieldValue(field.name, event?.target?.value);
            handleSetTouched(field.name);
        },
        [field.name],
    );

    return (
        <Form.Group controlId={field.name}>
            {field.label && <Form.Label>{field.label}</Form.Label>}
            <Form.Control
                type={field.type}
                required={field.isRequired}
                name={field.name}
                disabled={isGeneratedText || field.disabled}
                value={field.default || value}
                style={style && style}
                autoComplete={field.autoComplete}
                className="w-100"
                onChange={isGeneratedText ? undefined : handleChange}
                isInvalid={!!error}
            />
            {field.subLabel && <span>{field.subLabel}</span>}
            {helperText && <span>{helperText}</span>}
            {error && <span className="danger">{error}</span>}
        </Form.Group>
    );
};

export default SwayText;
