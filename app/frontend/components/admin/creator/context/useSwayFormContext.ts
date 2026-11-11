import { InertiaFormProps } from "@inertiajs/react";
import { useContext } from "react";
import SwayFormContext from "app/frontend/components/admin/creator/context/SwayFormContext";

export const useSwayFormContext = <T extends Record<string, any> = Record<string, any>>() => {
    const context = useContext(SwayFormContext);
    if (!context) {
        throw new Error("useSwayFormContext must be used within a SwayFormContext.Provider");
    }
    return context as unknown as InertiaFormProps<T>;
};
