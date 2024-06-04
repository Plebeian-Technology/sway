import { useWebAuthnRegistration } from "app/frontend/hooks/authentication/useWebAuthnRegistration";
import { useAxios_NOT_Authenticated_POST_PUT } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/sway_utils";
import { useCallback } from "react";
import { sway } from "sway";

export const useConfirmPhoneVerification = (onAuthenticated: (user: sway.IUser) => void) => {
    const { startRegistration, verifyRegistration } = useWebAuthnRegistration(onAuthenticated);

    const { post: put, isLoading } = useAxios_NOT_Authenticated_POST_PUT<sway.IValidationResult>(
        "/phone_verification/0",
        { method: "put" },
    );

    const confirm = useCallback(
        (phone: string, code: string) => {
            put({ phone, code })
                .then((result) => {
                    if (result?.success) {
                        startRegistration(phone)
                            .then(async (publicKey) => {
                                if (!publicKey) {
                                    return;
                                }

                                await verifyRegistration(phone, publicKey).catch(handleError);
                            })
                            .catch(handleError);
                    } else {
                        notify({
                            level: "error",
                            title: "Incorrect Code",
                        });
                    }
                })
                .catch(handleError);
        },
        [put, startRegistration, verifyRegistration],
    );

    return { confirm, isLoading };
};
