import { router } from "@inertiajs/react";
import { useCallback } from "react";
import { handleError } from "../../sway_utils";
import { useAxios_NOT_Authenticated_GET } from "../useAxios";

export const useLogout = () => {
    const { get: logout } = useAxios_NOT_Authenticated_GET<Record<string, any>>("/users/webauthn/sessions/0", {
        method: "delete",
        skipInitialRequest: true,
    });

    return useCallback(() => {
        logout({})
            .then(() => {
                localStorage.clear();
                sessionStorage.clear();
                router.visit("/", { replace: true });
            })
            .catch(handleError);
    }, [logout]);
};
