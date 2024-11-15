import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import SwayTextArea from "app/frontend/components/forms/SwayTextArea";
import { useLocale } from "app/frontend/hooks/useLocales";
import { useFormikContext } from "formik";
import { useCallback } from "react";
import { Form } from "react-bootstrap";

const TextAreaField: React.FC<IFieldProps> = ({ swayField, fieldGroupLength }) => {
    const [locale] = useLocale();
    const errorMessage = useErrorMessage();
    const { values, setFieldValue, touched, setTouched } = useFormikContext();

    const handleSetTouched = useCallback(
        (fieldname: string) => {
            if ((touched as Record<string, any>)[fieldname]) return;
            setTouched({
                ...touched,
                [fieldname]: true,
            }).catch(console.error);
        },
        [setTouched, touched],
    );

    return (
        <Form.Group
            key={swayField.name}
            controlId={swayField.name}
            className={`col-xs-12 col-sm-${swayField.colClass || (12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4)}`}
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
                value={(values as Record<string, any>)[swayField.name] || ""}
                error={errorMessage(swayField.name)}
                setFieldValue={setFieldValue}
                handleSetTouched={handleSetTouched}
                helperText={swayField.helperText}
                rows={swayField.rows}
            />
        </Form.Group>
    );
};

export default TextAreaField;
