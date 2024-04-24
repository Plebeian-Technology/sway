import * as webauthnJson from "@github/webauthn-json";
import { AxiosResponse } from "axios";
import { IValidationResult } from "lobbie";
import { useCallback, useState } from "react";
import { useAxiosPublicPost } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/utils";

export const useWebAuthn2FARegistration = (id: number) => {
    const poster = useAxiosPublicPost();
    const [isRegistered, setRegistered] = useState<boolean>(false);
    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const startRegistration = useCallback(async () => {
        setLoading(true);
        return poster("/api/authentication/webauthn/registration/create", { id })
            .then((response: AxiosResponse | void) => {
                if (!response) {
                    setLoading(false);
                    return;
                }
                const result = response?.data as webauthnJson.CredentialCreationOptionsJSON;
                if (result) {
                    return webauthnJson.create(result).catch((e) => {
                        setLoading(false);
                        handleError(e);
                    });
                } else {
                    setLoading(false);
                }
            })
            .catch((e) => {
                setLoading(false);
                handleError(e);
            });
    }, [poster, id]);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyRegistration = useCallback(
        async (publicKeyCredential: webauthnJson.PublicKeyCredentialWithAttestationJSON) => {
            if (!publicKeyCredential) {
                setLoading(false);
                return;
            }

            return poster("/api/authentication/webauthn/registration/update", {
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
                    setRegistered(!!result?.success);
                    if (result) {
                        if (result.success) {
                            notify({
                                level: "success",
                                title: "Registered 2FA",
                            });
                        } else {
                            notify({
                                level: "error",
                                title: "Failed to register 2FA",
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
        startRegistration,
        verifyRegistration,
        isRegistered,
        isLoading,
    };
};
