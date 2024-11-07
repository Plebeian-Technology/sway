import { logDev } from "app/frontend/sway_utils";
import { useFormikContext } from "formik";
import { get } from "lodash";
import { useCallback } from "react";

export const useErrorMessage = () => {
    const { errors, touched } = useFormikContext();

    return useCallback(
        (fieldname: string): string => {
            if (!fieldname || !errors || !(touched as Record<string, any>)[fieldname]) return "";

            const error = get(errors, fieldname);
            if (!error) return "";

            logDev("BillCreatorField.errorMessage -", { error, fieldname });

            if (Array.isArray(error)) {
                return (error as string[]).find((e) => e === fieldname) || "";
            } else {
                return error as string;
            }
        },
        [errors, touched],
    );
};
