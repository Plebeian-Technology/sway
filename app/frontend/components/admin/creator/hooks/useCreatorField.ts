import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import { useCallback, useMemo } from "react";
import { sway } from "sway";
import { useSwayFormContext } from "app/frontend/components/admin/creator/context/useSwayFormContext";
import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";

export const useCreatorField = <T>(swayField: sway.IFormField<T>) => {
    const { data, setData, errors } = useSwayFormContext<IApiBillCreator>();
    const [locale] = useSwayLocale();
    const errorMessage = useErrorMessage(swayField);
    const error = errorMessage || (errors as Record<string, string> | undefined)?.[swayField.name as string];

    const disabled = Boolean(swayField.disabled || swayField.disableOn?.(locale));
    const value = (data as unknown as Record<string, unknown>)?.[swayField.name as string];

    const setValue = useCallback(
        (nextValue: unknown) => {
            setData(swayField.name as never, nextValue as never);
        },
        [setData, swayField.name],
    );

    return useMemo(
        () => ({
            data,
            setData,
            errors,
            locale,
            errorMessage,
            error,
            disabled,
            value,
            setValue,
        }),
        [data, setData, errors, locale, errorMessage, error, disabled, value, setValue],
    );
};
