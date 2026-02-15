import { useFetch } from "app/frontend/hooks/useFetch";

import {
    get,
    handleError,
    logDev,
    PublicKeyCredentialRequestOptionsJSON,
    PublicKeyCredentialWithAssertionJSON,
} from "app/frontend/sway_utils";
import { useCallback, useState } from "react";
import { sway } from "sway";

const AUTHENTICATE_ROUTE = "/users/webauthn/sessions";
const VERIFY_ROUTE = "/users/webauthn/sessions/callback";

export const useWebAuthnAuthentication = (onAuthenticated: (user: sway.IUser) => void) => {
    const authenticate = useFetch<PublicKeyCredentialRequestOptionsJSON | sway.IValidationResult>(AUTHENTICATE_ROUTE);
    const verify = useFetch<sway.IUser>(VERIFY_ROUTE);

    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#4-authentication
    const startAuthentication = useCallback(
        async (phone: string): Promise<PublicKeyCredentialWithAssertionJSON | boolean | void> => {
            const controller = new AbortController();

            setLoading(true);
            return authenticate({ phone })
                .then(async (result) => {
                    if (!result) return;

                    if ("success" in result) {
                        return result.success;
                    }

                    return get({ publicKey: result, signal: controller.signal }).catch((e) => {
                        handleError(e);
                    });
                })
                .catch((e) => {
                    // handleError(e);
                    throw e;
                })
                .finally(() => {
                    setLoading(false);
                });
        },
        [authenticate],
    );

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyAuthentication = useCallback(
        async (phone: string, publicKeyCredential: PublicKeyCredentialWithAssertionJSON) => {
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
                        logDev(
                            "useWebAuthnAuthentication.verifyAuthentication.verify - Verified Auth. Calling onAuthenticated with result -",
                            result,
                        );
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
        isLoading,
    };
};
