import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useLocale } from "app/frontend/hooks/useLocales";
import { useFormikContext } from "formik";
import { values } from "lodash";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import DatePicker from "react-datepicker";

const DateField: React.FC<IFieldProps> = ({ swayField, fieldGroupLength }) => {
    const { setFieldValue } = useFormikContext();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage();

    const maxDate = useMemo(() => {
        const date = new Date();
        date.setHours(date.getHours() + 24);
        return date;
    }, []);

    const minDate = useMemo(() => {
        const date = new Date();
        date.setFullYear(date.getFullYear() - 1);
        return date;
    }, []);

    const onChange = useCallback(
        (changed: Date | null) => {
            if (changed) {
                setFieldValue(swayField.name, changed).catch(console.error);
            }
        },
        [setFieldValue, swayField.name],
    );

    return (
        <Form.Group
            key={swayField.name}
            controlId={swayField.name}
            className={`col-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}
        >
            <Form.Label className="bold my-0">
                {swayField.label}
                {swayField.isRequired ? " *" : " (Optional)"}
            </Form.Label>
            <div className="my-2">
                <DatePicker
                    className="form-control z-100"
                    calendarClassName="z-100"
                    wrapperClassName="z-100"
                    placeholderText={"Select date..."}
                    disabled={swayField.disabled || swayField.disableOn?.(locale)}
                    minDate={minDate}
                    maxDate={maxDate}
                    selected={(values as Record<string, any>)[swayField.name]}
                    onChange={onChange}
                />
            </div>
            {swayField.helperText && <div className="text-muted">{swayField.helperText}</div>}
            <div className="text-danger">{errorMessage(swayField.name)}</div>
        </Form.Group>
    );
};

export default DateField;
