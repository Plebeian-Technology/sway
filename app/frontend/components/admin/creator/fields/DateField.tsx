import { FieldShell } from "app/frontend/components/admin/creator/fields/FieldShell";
import { useCreatorField } from "app/frontend/components/admin/creator/hooks/useCreatorField";
import { Input } from "app/frontend/components/ui/input";
import { useMaxMinTime } from "app/frontend/hooks/useMaxMinTime";
import { notify } from "app/frontend/sway_utils";
import { isValidDate } from "app/frontend/sway_utils/datetimes";
import { useCallback } from "react";
import { sway } from "sway";

interface IProps<T> {
    swayField: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

// @lat: [[bill-creator-shared-field-design#Why DateField wraps the shared Input component]]
const DateField = <T,>({ swayField, onBlur }: IProps<T>) => {
    const { setValue, errorMessage, disabled, value } = useCreatorField(swayField);

    const { maxDate, minDate } = useMaxMinTime();

    const onChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const val = e.target.value;
            if (!val) {
                // @lat: [[bill-creator-shared-field-design#Why a cleared date input saves null instead of stopping early]]
                setValue(null);
                return;
            }

            const changed = new Date(val);
            if (isValidDate(changed)) {
                try {
                    setValue(changed.toISOString());
                } catch (err) {
                    notify({
                        level: "error",
                        title: `Error setting date for field - ${swayField.label}. Please try again.`,
                    });
                    setValue(null);
                    console.error(err);
                }
            }
        },
        [setValue, swayField.label],
    );

    const dateValue = value ? (typeof value === "string" ? new Date(value) : new Date(value as Date)) : null;
    const dateString = dateValue && isValidDate(dateValue) ? dateValue.toISOString().split("T")[0] : "";

    return (
        <FieldShell
            name={swayField.name as string}
            label={swayField.label}
            required={swayField.isRequired}
            helperText={swayField.helperText}
            error={errorMessage}
        >
            <Input
                id={swayField.name as string}
                name={swayField.name as string}
                type="date"
                className="tabular-nums lining-nums"
                min={minDate.toISOString().split("T")[0]}
                max={maxDate.toISOString().split("T")[0]}
                value={dateString}
                onChange={onChange}
                onBlur={onBlur}
                disabled={disabled}
                aria-invalid={errorMessage ? true : undefined}
                aria-describedby={errorMessage ? `${swayField.name as string}-error` : undefined}
            />
        </FieldShell>
    );
};

export default DateField;
