/** @format */

import { useFormikContext } from "formik";
import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    style?: React.CSSProperties;
    helperText?: string;
}

const SwayText: React.FC<IProps> = ({ field, value, error, style, helperText }) => {
    const { handleChange } = useFormikContext();

    const isGeneratedText = field.component === "generatedText";

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
