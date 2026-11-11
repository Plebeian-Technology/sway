import { logDev } from "app/frontend/sway_utils";
import { get } from "lodash";
import { useMemo } from "react";
import { sway } from "sway";
import { useSwayFormContext } from "app/frontend/components/admin/creator/context/useSwayFormContext";

export const useErrorMessage = <T>(swayField: sway.IFormField<T>) => {
    const { errors } = useSwayFormContext();

    return useMemo(() => {
        if (!swayField?.name || !errors) return "";

        const error = get(errors, swayField.name);
        if (!error) return "";

        logDev("V2BillCreatorField.errorMessage -", { error, fieldname: swayField.name });

        if (Array.isArray(error)) {
            // @lat: [[bill-form-field-error-message-joining#Why useErrorMessage joins list-shaped errors]]
            return (error as string[]).filter(Boolean).join(", ");
        } else {
            return error as string;
        }
    }, [errors, swayField]);
};
