import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { ISubmitValues } from "app/frontend/components/admin/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import SwaySelect from "app/frontend/components/forms/SwaySelect";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName, toSelectOption } from "app/frontend/sway_utils";

const LocaleField = <T,>({ swayField, fieldGroupLength }: IFieldProps<T>) => {
    const { setData: setFieldValue } = useFormContext<ISubmitValues>();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage(swayField);

    return (
        <div key={swayField.name} className={`col-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}>
            <SwaySelect
                field={swayField}
                error={errorMessage}
                handleSetTouched={() => null}
                setFieldValue={(fname, fvalue) => {
                    setFieldValue(fname, fvalue);
                }}
                value={toSelectOption(toFormattedLocaleName(locale.name), locale.id)}
                helperText={swayField.helperText}
            />
        </div>
    );
};

export default LocaleField;
