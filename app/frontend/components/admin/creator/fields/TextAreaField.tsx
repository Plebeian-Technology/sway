import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import SwayTextArea from "app/frontend/components/forms/SwayTextArea";
import { useLocale } from "app/frontend/hooks/useLocales";
import { Form } from "react-bootstrap";

const TextAreaField = <T,>({ swayField, fieldGroupLength }: IFieldProps<T>) => {
    const [locale] = useLocale();
    const errorMessage = useErrorMessage(swayField);
    const { data } = useFormContext();

    return (
        <Form.Group
            key={swayField.name}
            controlId={swayField.name}
            className={`col-xs-12 col-sm-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}
        >
            <Form.Label className="bold">
                {swayField.label}
                {swayField.isRequired ? " *" : " (Optional)"}
            </Form.Label>
            <SwayTextArea
                field={{
                    ...swayField,
                    disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                }}
                value={(data as Record<string, any>)[swayField.name] || ""}
                error={errorMessage}
                helperText={swayField.helperText}
                rows={swayField.rows}
            />
        </Form.Group>
    );
};

export default TextAreaField;
