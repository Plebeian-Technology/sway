import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IApiBillCreator, IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { useLocale } from "app/frontend/hooks/useLocales";
import { notify } from "app/frontend/sway_utils";
import { isValidDate } from "app/frontend/sway_utils/datetimes";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import { KeyOf } from "sway";

const DateField = <T,>({ swayField, fieldGroupLength, onBlur }: IFieldProps<T>) => {
    const { data, setData } = useFormContext<IApiBillCreator>();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage(swayField);

    const maxDate = useMemo(() => {
        const d = new Date();
        d.setHours(d.getHours() + 24);
        return d;
    }, []);

    const minDate = useMemo(() => {
        const d = new Date();
        d.setFullYear(d.getFullYear() - 4);
        return d;
    }, []);

    const onChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const val = e.target.value;
            if (!val) {
                return;
            }
            // new Date('YYYY-MM-DD') is parsed as UTC
            const changed = new Date(val);
            if (isValidDate(changed)) {
                try {
                    setData(swayField.name as KeyOf<IApiBillCreator>, changed.toISOString());
                } catch (error) {
                    notify({
                        level: "error",
                        title: `Error setting date for field - ${swayField.label}. Please try again.`,
                    });
                    setData(swayField.name as KeyOf<IApiBillCreator>, null);
                    console.error(error);
                }
            }
        },
        [setData, swayField.label, swayField.name],
    );

    const value = (data as Record<string, any>)[swayField.name];
    const dateValue = value ? (typeof value === "string" ? new Date(value) : new Date(value)) : null;
    // We use UTC date part because the input generates UTC midnight for date strings
    const dateString = dateValue && isValidDate(dateValue) ? dateValue.toISOString().split("T")[0] : "";

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
                <input
                    type="date"
                    className="form-control"
                    disabled={swayField.disabled || swayField.disableOn?.(locale)}
                    min={minDate.toISOString().split("T")[0]}
                    max={maxDate.toISOString().split("T")[0]}
                    value={dateString}
                    onChange={onChange}
                    onBlur={onBlur}
                />
            </div>
            {swayField.helperText && <div className="text-muted">{swayField.helperText}</div>}
            <div className="text-danger">{errorMessage}</div>
        </Form.Group>
    );
};

export default DateField;
