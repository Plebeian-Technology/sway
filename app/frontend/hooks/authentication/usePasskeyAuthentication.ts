import * as webauthnJson from "@github/webauthn-json";
import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { useThrottleAsyncFunction } from "app/frontend/hooks/useThrottle";
import { DEFAULT_ERROR_MESSAGE, handleError, logDev, notify } from "app/frontend/sway_utils";
import { isFailedRequest } from "app/frontend/sway_utils/http";
import { PublicKeyCredentialRequestOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";
import { useCallback, useEffect, useState } from "react";
import { sway } from "sway";

export const usePasskeyAuthentication = (onAuthenticated: (user: sway.IUserWithSettingsAdmin) => void) => {
    const {
        post: authenticate,
        items: authOptions,
        setItems: setAuthOptions,
    } = useAxios_NOT_Authenticated_POST<PublicKeyCredentialRequestOptionsJSON>("/users/webauthn/passkeys");

    const { post: verify } = useAxios_NOT_Authenticated_POST<sway.IUserWithSettingsAdmin>(
        "/users/webauthn/passkeys/callback",
    );

    const [isLoading, setLoading] = useState<boolean>(false);

    const getPasskey = useCallback(async () => {
        if (
            !window?.PublicKeyCredential?.isConditionalMediationAvailable ||
            !window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable
        ) {
            logDev("window?.PublicKeyCredential?.isConditionalMediationAvailable IS NOT IN WINDOW");
            return;
        }

        const authenticatorAvailable = await window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
        if (!authenticatorAvailable) {
            logDev("window?.PublicKeyCredential?.isUserVerifyingPlatformAuthenticatorAvailable IS NOT AVAILABLE");
            return;
        }

        // Check if conditional mediation is available.
        await window.PublicKeyCredential.isConditionalMediationAvailable()
            .then(async (isAvailable) => {
                if (!isAvailable) {
                    logDev("window?.PublicKeyCredential?.isConditionalMediationAvailable IS NOT AVAILABLE");
                    return;
                }

                setLoading(true);

                // Retrieve authentication options for `navigator.credentials.get()`
                // from your server.
                await authenticate({});

                // This call to `navigator.credentials.get()` is "set and forget."
                // The Promise will only resolve if the user successfully interacts
                // with the browser's autofill UI to select a passkey.
                // const webAuthnResponse = await navigator.credentials.get({
                //     mediation: "conditional",
                //     publicKey: {
                //         ...authOptions,
                //         userVerification: "preferred",
                //     },
                // });
            })
            .catch(console.error);
    }, [authenticate]);

    const verifyPasskey = useCallback(() => {
        if (!authOptions) return;

        const result = {
            publicKey: {
                ...authOptions,
            },
            mediation: "conditional",
            // userVerification: "preferred",
        } as webauthnJson.CredentialRequestOptionsJSON;

        const controller = new AbortController();

        webauthnJson
            .get({ ...result, signal: controller.signal })
            .then((publicKeyCredential) => {
                verify({
                    ...publicKeyCredential,
                    challenge: result.publicKey?.challenge,
                })
                    .then((res) => {
                        // setLoading(false);
                        if (!res || isFailedRequest(res)) {
                            notify({
                                level: "error",
                                title: "Failed to login with passkey.",
                                message: (res as sway.IValidationResult | null)?.message || DEFAULT_ERROR_MESSAGE,
                            });
                        } else {
                            onAuthenticated(res as sway.IUserWithSettingsAdmin);
                        }
                    })
                    .catch((e) => {
                        // setLoading(false);
                        handleError(e);
                    });
            })
            .catch((e) => {
                console.error(e);
            });
    }, [authOptions, onAuthenticated, verify]);

    const authenticate_throttled = useThrottleAsyncFunction(authenticate);

    useEffect(() => {
        authenticate_throttled({} as Record<string, any>).catch(console.error);
    }, [authenticate_throttled]);

    useEffect(() => {
        verifyPasskey();
    }, [verifyPasskey]);

    return { isLoading, getPasskey, setAuthOptions };
};
