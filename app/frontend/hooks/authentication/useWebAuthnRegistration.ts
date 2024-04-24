import * as webauthnJson from "@github/webauthn-json";
import { useCallback, useState } from "react";
import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/sway_utils";
import { sway } from "sway";
import {
    PublicKeyCredentialCreationOptionsJSON,
    PublicKeyCredentialRequestOptionsJSON,
} from "node_modules/@github/webauthn-json/dist/types/basic/json";

export const useWebAuthnRegistration = (onAuthenticated: (user: sway.IUserWithSettingsAdmin) => void) => {
    const { post: creater } =
        useAxios_NOT_Authenticated_POST<PublicKeyCredentialCreationOptionsJSON>("/sign_up/new_challenge");
    const { post: updater } = useAxios_NOT_Authenticated_POST<sway.IValidationResult>("/users");

    const [isRegistered, setRegistered] = useState<boolean>(false);
    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const startRegistration = useCallback(
        async (email: string) => {
            setLoading(true);
            return creater({ user: { email, passkey_label: email } })
                .then((result) => {
                    if (result) {
                        return webauthnJson
                            .create({ publicKey: result } as webauthnJson.CredentialCreationOptionsJSON)
                            .catch((e) => {
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
        },
        [creater],
    );

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const verifyRegistration = useCallback(
        async (email: string, publicKeyCredential: webauthnJson.PublicKeyCredentialWithAttestationJSON) => {
            if (!email || !publicKeyCredential) {
                setLoading(false);
                return;
            }

            return updater({
                user: { email, passkey_label: email }, passkey: { ...publicKeyCredential, sign_count: 0, raw_id: publicKeyCredential.rawId, public_key: publicKeyCredential },
            })
                .then((result) => {
                    setLoading(false);
                    setRegistered(!!result?.success);

                    if (result) {
                        if (result.success && result.data) {
                            notify({
                                level: "success",
                                title: "Passkey Created",
                            });
                            onAuthenticated(result.data as sway.IUserWithSettingsAdmin);
                        } else {
                            notify({
                                level: "error",
                                title: "Failed to register Passkey",
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
        [onAuthenticated, updater],
    );

    return {
        startRegistration,
        verifyRegistration,
        isRegistered,
        isLoading,
    };
};
