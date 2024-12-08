import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import SwayText from "app/frontend/components/forms/SwayText";
import { useLocale } from "app/frontend/hooks/useLocales";
import { useMemo } from "react";

const TextField = <T,>({ swayField, fieldGroupLength, onBlur }: IFieldProps<T>) => {
    const { data } = useFormContext();
    const [locale] = useLocale();
    const errorMessage = useErrorMessage(swayField);

    const generatedValue = useMemo(() => {
        if (swayField.component === "generatedText" && swayField.generateFields) {
            return swayField.generateFields
                .map((fieldname: string) => (data as Record<string, any>)[fieldname])
                .join(swayField.joiner || " ");
        }
        return "";
    }, [data, swayField]);

    const value = swayField.component === "text" ? (data as Record<string, any>)[swayField.name] : generatedValue;

    return (
        <div
            key={swayField.name}
            className={`my-3 col-xs-12 col-sm-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}
        >
            <SwayText
                field={{
                    ...swayField,
                    disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                }}
                value={value}
                error={errorMessage}
                helperText={swayField.helperText}
                onBlur={onBlur}
            />
        </div>
    );
};

export default TextField;
