import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import SwayText from "app/frontend/components/forms/SwayText";
import { useLocale } from "app/frontend/hooks/useLocales";
import { useFormikContext } from "formik";
import { useMemo } from "react";

const TextField: React.FC<IFieldProps> = ({ swayField, fieldGroupLength }) => {
    const { values } = useFormikContext();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage();

    const generatedValue = useMemo(() => {
        if (swayField.component === "generatedText" && swayField.generateFields) {
            return swayField.generateFields
                .map((fieldname: string) => (values as Record<string, any>)[fieldname])
                .join(swayField.joiner || " ");
        }
        return "";
    }, [values, swayField]);

    const value = swayField.component === "text" ? (values as Record<string, any>)[swayField.name] : generatedValue;

    return (
        <div
            key={swayField.name}
            className={`my-3 col-${swayField.colClass || (12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4)}`}
        >
            <SwayText
                field={{
                    ...swayField,
                    disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                }}
                value={value}
                error={errorMessage(swayField.name)}
                helperText={swayField.helperText}
            />
        </div>
    );
};

export default TextField;
