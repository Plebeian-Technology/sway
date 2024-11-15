import { DatePicker } from "@mui/x-date-pickers";
import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useLocale } from "app/frontend/hooks/useLocales";
import dayjs, { Dayjs } from "dayjs";
import { useFormikContext } from "formik";
import { values } from "lodash";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";

const DateField: React.FC<IFieldProps> = ({ swayField, fieldGroupLength }) => {
    const { setFieldValue } = useFormikContext();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage();

    const maxDate = useMemo(() => {
        return dayjs().add(24, "hours");
    }, []);

    const minDate = useMemo(() => {
        return dayjs().add(-4, "years");
    }, []);

    const onChange = useCallback(
        (changed: Dayjs | null) => {
            if (changed) {
                setFieldValue(swayField.name, changed).catch(console.error);
            }
        },
        [setFieldValue, swayField.name],
    );

    const value = (values as Record<string, any>)[swayField.name];

    return (
        <Form.Group
            key={swayField.name}
            controlId={swayField.name}
            className={`my-3 col-xs-12 col-sm-${swayField.colClass || (12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4)}`}
        >
            <Form.Label className="bold my-0">
                {swayField.label}
                {swayField.isRequired ? " *" : " (Optional)"}
            </Form.Label>
            <div className="my-2">
                <DatePicker
                    className="form-control"
                    disabled={swayField.disabled || swayField.disableOn?.(locale)}
                    minDate={minDate}
                    maxDate={maxDate}
                    value={value ? dayjs(value) : null}
                    onChange={onChange}
                />
            </div>
            {swayField.helperText && <div className="text-muted">{swayField.helperText}</div>}
            <div className="text-danger">{errorMessage(swayField.name)}</div>
        </Form.Group>
    );
};

export default DateField;
