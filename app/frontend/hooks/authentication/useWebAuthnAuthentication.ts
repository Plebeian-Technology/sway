import * as webauthnJson from "@github/webauthn-json";

import { useCallback, useState } from "react";
import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { DEFAULT_ERROR_MESSAGE, handleError, logDev, notify } from "app/frontend/sway_utils";
import { sway } from "sway";
import { PublicKeyCredentialRequestOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";

export const useWebAuthnAuthentication = (onAuthenticated: (user: sway.IUser) => void) => {
    const { post: authenticate } = useAxios_NOT_Authenticated_POST<PublicKeyCredentialRequestOptionsJSON>(
        "/users/webauthn/sessions",
        {
            errorHandler: (e) => {
                throw e;
            },
        },
    );
    const { post: verify } = useAxios_NOT_Authenticated_POST<sway.IUser>(
        "/users/webauthn/sessions/callback",
    );

    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#4-authentication
    const startAuthentication = useCallback(
        async (phone: string): Promise<webauthnJson.PublicKeyCredentialWithAssertionJSON | void> => {
            const controller = new AbortController();

            setLoading(true);
            return authenticate({ phone })
                .then((result) => {
                    if (result) {
                        return webauthnJson.get({ publicKey: result, signal: controller.signal, }).catch((e) => {
                            setLoading(false);
                            handleError(e);
                        });
                    }
                })
                .catch((e) => {
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
        ) => {
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
                    if (result) {
                        onAuthenticated(result as sway.IUser);
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
    }
};
