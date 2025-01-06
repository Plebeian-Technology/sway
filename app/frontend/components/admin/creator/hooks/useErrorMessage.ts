import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { logDev } from "app/frontend/sway_utils";
import { get } from "lodash";
import { useMemo } from "react";
import { sway } from "sway";

export const useErrorMessage = <T>(swayField: sway.IFormField<T>) => {
    const { errors } = useFormContext();

    return useMemo(() => {
        if (!swayField?.name || !errors) return "";

        const error = get(errors, swayField.name);
        if (!error) return "";

        logDev("BillCreatorField.errorMessage -", { error, fieldname: swayField.name });

        if (Array.isArray(error)) {
            return (error as string[]).find((e) => e === swayField.name) || "";
        } else {
            return error as string;
        }
    }, [errors, swayField]);
};
