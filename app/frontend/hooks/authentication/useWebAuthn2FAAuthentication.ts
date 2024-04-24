import * as webauthnJson from "@github/webauthn-json";
import { AxiosResponse } from "axios";
import { IValidationResult } from "lobbie";
import { useCallback, useState } from "react";
import { useAxiosPublicPost } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/utils";

export const useWebAuthn2FAAuthentication = (id: number) => {
    const poster = useAxiosPublicPost();
    const [isAuthenticated, setAuthenticated] = useState<boolean>(false);
    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#4-authentication
    const startAuthentication = useCallback(async () => {
        setLoading(true);
        return poster("/api/authentication/webauthn/authentication/create", { id })
            .then((response: AxiosResponse | void) => {
                if (!response) {
                    setLoading(false);
                    return;
                }
                const result = response?.data as webauthnJson.CredentialRequestOptionsJSON;
                if (result) {
                    return webauthnJson.get(result).catch((e) => {
                        setLoading(false);
                        handleError(e);
                    });
                }
            })
            .catch((e) => {
                setLoading(false);
                handleError(e);
            });
    }, [poster, id]);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyAuthentication = useCallback(
        async (
            publicKeyCredential: webauthnJson.PublicKeyCredentialWithAssertionJSON,
        ): Promise<IValidationResult | void> => {
            if (!publicKeyCredential) {
                setLoading(false);
                return;
            }

            return poster("/api/authentication/webauthn/authentication/update", {
                id,
                publicKeyCredential,
            })
                .then((response: AxiosResponse | void) => {
                    if (!response) {
                        setLoading(false);
                        return;
                    }
                    const result = response?.data as IValidationResult | undefined;
                    setLoading(false);
                    setAuthenticated(!!result?.success);
                    if (result) {
                        if (result.success) {
                            notify({
                                level: "success",
                                title: "Authenticated 2FA",
                            });
                        } else {
                            notify({
                                level: "error",
                                title: "Failed to authenticate 2FA",
                                message: result.message,
                            });
                        }
                    }
                    return result;
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                });
        },
        [poster, id],
    );

    return {
        startAuthentication,
        verifyAuthentication,
        isAuthenticated,
        isLoading,
    };
};
