/** @format */

import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { PropsWithChildren } from "react";
import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps<T> {
    field: sway.IFormField<T>;
    value: string;
    error: string;
    style?: React.CSSProperties;
    helperText?: string;
    disabled?: boolean;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

const SwayText = <T,>(props: IProps<T>) => {
    if (props.field.label) {
        return (
            <Form.Group controlId={props.field.name}>
                <SwayTextHeader {...props} />
                <SwayTextFloatingLabel {...props}>
                    <SwayTextInput {...props} />
                </SwayTextFloatingLabel>
            </Form.Group>
        );
    }

    return (
        <Form.Group controlId={props.field.name}>
            <SwayTextHeader {...props} />
            <SwayTextInput {...props} />
        </Form.Group>
    );
};

const SwayTextFloatingLabel = <T,>({ field, children }: IProps<T> & PropsWithChildren) => {
    return (
        <Form.FloatingLabel className="bold" label={getLabel(field)}>
            {children}
        </Form.FloatingLabel>
    );
};

const getLabel = <T,>(field?: sway.IFormField<T>) =>
    field?.label ? `${field.label}${field.isRequired ? " *" : "(Optional)"}` : "";

const SwayTextInput = <T,>({ disabled, field, value, error, onBlur, style }: IProps<T>) => {
    const { setData } = useFormContext();
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
            onChange={isGeneratedText ? undefined : (e) => setData(field.name, e.target.value)}
            onBlur={onBlur}
            isInvalid={!!error}
        />
    );
};

const SwayTextHeader = <T,>({ field, error, helperText }: IProps<T>) => {
    return (
        <div>
            {field.subLabel && <span className="bold">{field.subLabel}</span>}
            {helperText && <span className="bold">{helperText}</span>}
            {error && <span className="danger">{error}</span>}
        </div>
    );
};

// const SwayTextFooter: React.FC<IProps> = ({ field, error, helperText }) => {
//     return (
//         <>
//             {field.subLabel && <span className="bold">{field.subLabel}</span>}
//             {helperText && <span className="bold">{helperText}</span>}
//             {error && <span className="danger">{error}</span>}
//         </>
//     );
// };

export default SwayText;
