import * as webauthnJson from "@github/webauthn-json";

import { useAxios_NOT_Authenticated_POST_PUT } from "app/frontend/hooks/useAxios";
import { handleError } from "app/frontend/sway_utils";
import { PublicKeyCredentialRequestOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";
import { useCallback, useState } from "react";
import { sway } from "sway";

export const useWebAuthnAuthentication = (onAuthenticated: (user: sway.IUser) => void) => {
    const { post: authenticate } = useAxios_NOT_Authenticated_POST_PUT<PublicKeyCredentialRequestOptionsJSON | sway.IValidationResult>(
        "/users/webauthn/sessions",
        {
            errorHandler: (e) => {
                throw e;
            },
        },
    );
    const { post: verify } = useAxios_NOT_Authenticated_POST_PUT<sway.IUser>("/users/webauthn/sessions/callback");

    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#4-authentication
    const startAuthentication = useCallback(
        async (
            phone: string,
        ): Promise<webauthnJson.PublicKeyCredentialWithAssertionJSON | boolean | void> => {
            const controller = new AbortController();

            setLoading(true);
            return authenticate({ phone })
                .then(async(result) => {
                    if (!result) return;

                    if ("success" in result) {
                        return result.success;
                    }

                    return webauthnJson.get({ publicKey: result, signal: controller.signal }).catch((e) => {
                        handleError(e);
                    });
                })
                .catch((e) => {
                    // handleError(e);
                    throw e;
                }).finally(() => {
                    setLoading(false);
                });
        },
        [authenticate],
    );

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyAuthentication = useCallback(
        async (phone: string, publicKeyCredential: webauthnJson.PublicKeyCredentialWithAssertionJSON) => {
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
        isLoading
    };
};
