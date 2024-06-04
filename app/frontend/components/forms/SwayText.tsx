/** @format */

import { useFormikContext } from "formik";
import { PropsWithChildren } from "react";
import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: string;
    error: string;
    style?: React.CSSProperties;
    helperText?: string;
    disabled?: boolean;
}

const SwayText: React.FC<IProps> = (props) => {
    if (props.field.label) {
        return (
            <Form.Group controlId={props.field.name}>
                <SwayTextFloatingLabel {...props}>
                    <SwayTextInput {...props} />
                    <SwayTextFooter {...props} />
                </SwayTextFloatingLabel>
            </Form.Group>
        );
    }

    return (
        <Form.Group controlId={props.field.name}>
            <SwayTextInput {...props} />
            <SwayTextFooter {...props} />
        </Form.Group>
    );
};

const SwayTextFloatingLabel: React.FC<IProps & PropsWithChildren> = ({ field, children }) => {
    return (
        <Form.FloatingLabel className="bold" label={getLabel(field)}>
            {children}
        </Form.FloatingLabel>
    );
};

const getLabel = (field?: sway.IFormField) =>
    field?.label ? `${field.label}${field.isRequired ? " *" : "(Optional)"}` : "";

const SwayTextInput: React.FC<IProps> = ({ disabled, field, value, error, style }) => {
    const { handleChange } = useFormikContext();
    const isGeneratedText = field.component === "generatedText";

    return (
        <Form.Control
            type={field.type}
            required={field.isRequired}
            name={field.name}
            disabled={isGeneratedText || field.disabled || disabled}
            value={field.default || value}
            style={style}
            autoComplete={field.autoComplete}
            placeholder={getLabel(field)}
            className="w-100"
            onChange={isGeneratedText ? undefined : handleChange}
            isInvalid={!!error}
        />
    );
};

const SwayTextFooter: React.FC<IProps> = ({ field, error, helperText }) => {
    return (
        <>
            {field.subLabel && <span className="bold">{field.subLabel}</span>}
            {helperText && <span className="bold">{helperText}</span>}
            {error && <span className="danger">{error}</span>}
        </>
    );
};

export default SwayText;
