import { signOut } from "firebase/auth";
import { useCallback } from "react";
import { useNavigate } from "react-router";
import { auth } from "../../firebase";
import { handleError } from "../../sway_utils";

export const useLogout = () => {
    const navigate = useNavigate();
    return useCallback(() => {
        signOut(auth)
            .then(() => {
                localStorage.clear();
                sessionStorage.clear();
                navigate("/", { replace: true });
            })
            .catch(handleError);
    }, [navigate]);
};
export const useLogoutNoRedirect = (): (() => Promise<void>) => {
    return useCallback(async () => {
        return signOut(auth)
            .then(() => {
                localStorage.clear();
                sessionStorage.clear();
            })
            .catch(handleError);
    }, []);
};
