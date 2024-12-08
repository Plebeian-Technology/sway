import { DatePicker } from "@mui/x-date-pickers";
import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IApiBillCreator, IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { useLocale } from "app/frontend/hooks/useLocales";
import { add } from "date-fns";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import { KeyOf } from "sway";

const DateField = <T,>({ swayField, fieldGroupLength, onBlur }: IFieldProps<T>) => {
    const { data, setData } = useFormContext<IApiBillCreator>();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage(swayField);

    const maxDate = useMemo(() => {
        return add(new Date(), { hours: 24 });
    }, []);

    const minDate = useMemo(() => {
        return add(new Date(), { years: -4 });
    }, []);

    const onChange = useCallback(
        (changed: Date | null) => {
            if (changed) {
                setData(swayField.name as KeyOf<IApiBillCreator>, changed.toISOString());
            }
        },
        [setData, swayField.name],
    );

    const value = (data as Record<string, any>)[swayField.name];

    return (
        <Form.Group
            key={swayField.name}
            controlId={swayField.name}
            className={`my-3 col-xs-12 col-sm-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}
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
                    value={value ? new Date(value) : null}
                    onChange={onChange}
                    slotProps={{
                        textField: {
                            onBlur,
                        },
                    }}
                />
            </div>
            {swayField.helperText && <div className="text-muted">{swayField.helperText}</div>}
            <div className="text-danger">{errorMessage}</div>
        </Form.Group>
    );
};

export default DateField;
