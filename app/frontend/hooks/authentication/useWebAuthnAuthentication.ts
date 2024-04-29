import * as webauthnJson from "@github/webauthn-json";

import { useCallback, useState } from "react";
import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { DEFAULT_ERROR_MESSAGE, handleError, logDev, notify } from "app/frontend/sway_utils";
import { sway } from "sway";

export const useWebAuthnAuthentication = (onAuthenticated: (user: sway.IUserWithSettingsAdmin) => void) => {
    const { post: authenticate } = useAxios_NOT_Authenticated_POST<webauthnJson.CredentialRequestOptionsJSON>(
        "/users/webauthn/sessions",
        {
            errorHandler: (e) => {
                throw e;
            },
        },
    );
    const { post: verify } = useAxios_NOT_Authenticated_POST<sway.IValidationResult>(
        "/users/webauthn/sessions/callback",
    );

    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#4-authentication
    const startAuthentication = useCallback(
        async (phone: string) => {
            setLoading(true);
            return authenticate({ phone })
                .then((result) => {
                    if (result) {
                        return webauthnJson.get(result).catch((e) => {
                            setLoading(false);
                            handleError(e);
                        });
                    }
                })
                .catch((e) => {
                    logDev("eeeeeeee1", e)
                    setLoading(false);
                    // handleError(e);
                    throw e;
                });
        },
        [authenticate],
    );

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyAuthentication = useCallback(
        async (
            phone: string,
            publicKeyCredential: webauthnJson.PublicKeyCredentialWithAssertionJSON,
        ): Promise<sway.IValidationResult | null | void> => {
            if (!publicKeyCredential) {
                setLoading(false);
                return;
            }

            return verify({
                phone,
                publicKeyCredential,
            })
                .then((result) => {
                    setLoading(false);
                    if (result && result.data) {
                        onAuthenticated(result.data as sway.IUserWithSettingsAdmin);
                    } else {
                        notify({
                            level: "error",
                            title: "Failed to authenticate.",
                            message: (result as sway.IValidationResult).message || DEFAULT_ERROR_MESSAGE,
                        });
                    }
                    return result;
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                });
        },
        [verify, onAuthenticated],
    );

    return {
        startAuthentication,
        verifyAuthentication,
        isLoading,
    };
};
