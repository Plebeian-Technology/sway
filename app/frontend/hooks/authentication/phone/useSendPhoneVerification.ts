import { useAxios_NOT_Authenticated_POST_PUT } from "app/frontend/hooks/useAxios";
import { handleError } from "app/frontend/sway_utils";
import { useCallback } from "react";
import { sway } from "sway";

export const useSendPhoneVerification = () => {
    const { post, isLoading } = useAxios_NOT_Authenticated_POST_PUT<sway.IValidationResult>("/phone_verification", {
        method: "post",
    });

    const send = useCallback(
        (phone: string) => {
            return post({ phone })
                .then((result) => result?.success)
                .catch(handleError);
        },
        [post],
    );

    return { send, isLoading };
};
