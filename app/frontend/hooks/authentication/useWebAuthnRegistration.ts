import * as webauthnJson from "@github/webauthn-json";
import { useCallback, useState } from "react";
import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { handleError, notify } from "app/frontend/sway_utils";
import { sway } from "sway";
import { PublicKeyCredentialCreationOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";

export const useWebAuthnRegistration = (onAuthenticated: (user: sway.IUser) => void) => {
    const { post: creater } =
        useAxios_NOT_Authenticated_POST<PublicKeyCredentialCreationOptionsJSON>("/users/webauthn/registration");
    const { post: updater } = useAxios_NOT_Authenticated_POST<sway.IUser>(
        "/users/webauthn/registration/callback",
    );
    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const startRegistration = useCallback(
        async (phone: string) => {
            const controller = new AbortController();
            
            setLoading(true);
            return creater({ phone, passkey_label: "Sway" })
                .then((result) => {
                    if (result) {
                        return webauthnJson.create({ publicKey: result, signal: controller.signal }).catch((e) => {
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
                passkey_label: "Sway",
                ...publicKeyCredential,
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
        [onAuthenticated, updater],
    );

    return {
        startRegistration,
        verifyRegistration,
        isLoading,
    };
};
