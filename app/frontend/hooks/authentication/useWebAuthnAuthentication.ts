import * as webauthnJson from "@github/webauthn-json";

import { useAxios_NOT_Authenticated_POST_PUT } from "app/frontend/hooks/useAxios";
import { handleError, logDev } from "app/frontend/sway_utils";
import { PublicKeyCredentialRequestOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { UseInertiaFormProps } from "use-inertia-form";

export const useWebAuthnAuthentication = (
    verify: UseInertiaFormProps<
        sway.IUser & { publicKeyCredential?: webauthnJson.PublicKeyCredentialWithAssertionJSON }
    >["post"],
    transform: UseInertiaFormProps<
        sway.IUser & { publicKeyCredential?: webauthnJson.PublicKeyCredentialWithAssertionJSON }
    >["transform"],
    onAuthenticated: (user: sway.IUser) => Promise<void>,
) => {
    const { post: authenticate } = useAxios_NOT_Authenticated_POST_PUT<
        PublicKeyCredentialRequestOptionsJSON | sway.IValidationResult
    >("/users/webauthn/sessions", {
        errorHandler: (e) => {
            throw e;
        },
    });

    // const { post: verify } = useAxios_NOT_Authenticated_POST_PUT<sway.IUser>("/users/webauthn/sessions/callback");

    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#4-authentication
    const startAuthentication = useCallback(
        async (phone: string): Promise<webauthnJson.PublicKeyCredentialWithAssertionJSON | boolean | void> => {
            const controller = new AbortController();

            setLoading(true);
            return authenticate({ phone })
                .then(async (result) => {
                    if (!result) return;

                    if ("success" in result) {
                        return result.success;
                    }

                    return webauthnJson.get({ publicKey: result, signal: controller.signal }).catch((e: Error) => {
                        setLoading(false);
                        if (e.name === "AbortError") {
                            // noop
                        } else {
                            handleError(e);
                        }
                    });
                })
                .catch((e) => {
                    // handleError(e);
                    throw e;
                })
                .finally(() => {
                    // setLoading(false);
                });
        },
        [authenticate],
    );

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyAuthentication = useCallback(
        (phone: string, publicKeyCredential: webauthnJson.PublicKeyCredentialWithAssertionJSON) => {
            if (!publicKeyCredential) {
                logDev("verifyAuthentication - no public key credential");
                setLoading(false);
                return;
            }

            transform((data) => ({
                ...data,
                phone,
                publicKeyCredential,
            }));

            return verify("/users/webauthn/sessions/callback", {
                onSuccess: () => {
                    onAuthenticated({ phone } as sway.IUser);
                },
                onError: (e) => {
                    console.error(e);
                },
                onFinish: () => {
                    setLoading(false);
                },
            });
            // .then((result) => {
            //     logDev("verifyAuthentication.callback.result -", result);
            //     if (result) {
            //         logDev(
            //             "useWebAuthnAuthentication.verifyAuthentication.verify - Verified Auth. Calling onAuthenticated with result -",
            //             result,
            //         );
            //         // onAuthenticated(result as sway.IUser)
            //         //     .then(() => {
            //         //         setLoading(false);
            //         //         return result;
            //         //     })
            //         //     .catch(console.error);
            //     } else {
            //         setLoading(false);
            //         return result;
            //     }
            // })
            // .catch((e) => {
            //     setLoading(false);
            //     handleError(e);
            // });
        },
        [transform, verify, onAuthenticated],
    );

    return {
        startAuthentication,
        verifyAuthentication,
        isLoading,
    };
};
