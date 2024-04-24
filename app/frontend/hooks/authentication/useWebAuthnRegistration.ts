import * as webauthnJson from "@github/webauthn-json";
import { useCallback, useState } from "react";
import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/sway_utils";
import { sway } from "sway";
import { PublicKeyCredentialCreationOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";

export const useWebAuthnRegistration = (onAuthenticated: (user: sway.IUserWithSettingsAdmin) => void) => {
    const { post: creater } =
        useAxios_NOT_Authenticated_POST<PublicKeyCredentialCreationOptionsJSON>("/users/webauthn/registration");
    const { post: updater } = useAxios_NOT_Authenticated_POST<sway.IUserWithSettingsAdmin>(
        "/users/webauthn/registration/callback",
    );
    const [isRegistered, setRegistered] = useState<boolean>(false);
    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const startRegistration = useCallback(
        async (phone: string) => {
            setLoading(true);
            return creater({ phone, passkey_label: phone })
                .then((result) => {
                    if (result) {
                        return webauthnJson.create({ publicKey: result }).catch((e) => {
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
        async (phone: string, publicKeyCredential: webauthnJson.PublicKeyCredentialWithAttestationJSON) => {
            if (!phone || !publicKeyCredential) {
                setLoading(false);
                return;
            }

            return updater({
                phone,
                passkey_label: phone,
                ...publicKeyCredential,
            })
                .then((result) => {
                    setLoading(false);

                    if (result) {
                        onAuthenticated(result as sway.IUserWithSettingsAdmin);
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
