import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import SwaySelect from "app/frontend/components/forms/SwaySelect";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toSelectOption, toFormattedLocaleName } from "app/frontend/sway_utils";
import { useFormikContext } from "formik";

const LocaleField: React.FC<IFieldProps> = ({ swayField, fieldGroupLength }) => {
    const { setFieldValue } = useFormikContext();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage();

    return (
        <div key={swayField.name} className={`col-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}>
            <SwaySelect
                field={swayField}
                error={errorMessage(swayField.name)}
                handleSetTouched={() => null}
                setFieldValue={(fname, fvalue) => {
                    setFieldValue(fname, fvalue).catch(console.error);
                }}
                value={toSelectOption(toFormattedLocaleName(locale.name), locale.id)}
                helperText={swayField.helperText}
            />
        </div>
    );
};

export default LocaleField;
