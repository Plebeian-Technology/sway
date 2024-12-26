import * as webauthnJson from "@github/webauthn-json";
import { useFetch } from "app/frontend/hooks/useFetch";
import { handleError } from "app/frontend/sway_utils";
import { PublicKeyCredentialCreationOptionsJSON } from "node_modules/@github/webauthn-json/dist/types/basic/json";
import { useCallback, useState } from "react";
import { sway } from "sway";

const REGISTRATION_ROUTE = "/users/webauthn/registration";
const CALLBACK_ROUTE = "/users/webauthn/registration/callback";

export const useWebAuthnRegistration = (onAuthenticated: (user: sway.IUser) => void) => {
    const creater = useFetch<PublicKeyCredentialRequestOptionsJSON | sway.IValidationResult>(REGISTRATION_ROUTE);
    const updater = useFetch<sway.IUser>(CALLBACK_ROUTE);

    const [isLoading, setLoading] = useState<boolean>(false);

    // https://github.com/Yubico/java-webauthn-server/#3-registration
    const startRegistration = useCallback(
        async (phone: string) => {
            const controller = new AbortController();

            setLoading(true);
            return creater({ phone, passkey_label: "Sway" })
                .then((result) => {
                    const r = result as PublicKeyCredentialCreationOptionsJSON;
                    if (r) {
                        return webauthnJson.create({ publicKey: r, signal: controller.signal }).catch((e) => {
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
