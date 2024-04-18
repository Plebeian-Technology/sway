import * as webauthnJson from "@github/webauthn-json";
import { useAxios_NOT_Authenticated_GET, useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { DEFAULT_ERROR_MESSAGE, handleError, notify } from "app/frontend/sway_utils";
import { isFailedRequest } from "app/frontend/sway_utils/http";
import { useCallback, useEffect, useState } from "react";
import { sway } from "sway";


export const usePasskeyAuthentication = (onAuthenticated: (user: sway.IUserWithSettingsAdmin) => void) => {
    const { get: getter } = useAxios_NOT_Authenticated_GET<webauthnJson.CredentialRequestOptionsJSON>("/users/passkeys");
    const { post: poster } = useAxios_NOT_Authenticated_POST<sway.IUserWithSettingsAdmin>("/users/passkeys");
    const [isLoading, setLoading] = useState<boolean>(false);

    const authenticatePasskey = useCallback(() => {
        if (
            window.PublicKeyCredential &&
            window.PublicKeyCredential.isConditionalMediationAvailable
        ) {
            // Check if conditional mediation is available.
            window.PublicKeyCredential.isConditionalMediationAvailable()
                .then((isAvailable) => {
                    if (!isAvailable) return;

                    setLoading(true);

                    getter()
                        .then(async (_result) => {
                            if (!_result) {
                                setLoading(false);
                                return;
                            }

                            const result = _result as webauthnJson.CredentialRequestOptionsJSON;
                            result["mediation"] = "conditional";
                            const publicKeyCredential = await webauthnJson.get(result);

                            poster({
                                ...publicKeyCredential,
                                challenge: result.publicKey?.challenge,
                            })
                                .then((res) => {
                                    setLoading(false);
                                    if (isFailedRequest(res)) {
                                        notify({
                                            level: "error",
                                            title: "Failed to login with passkey.",
                                            message:
                                                (result as sway.IValidationResult)?.message ||
                                                DEFAULT_ERROR_MESSAGE,
                                        });
                                    } else {
                                        onAuthenticated(res as sway.IUserWithSettingsAdmin);
                                    }
                                })
                                .catch((e) => {
                                    setLoading(false);
                                    handleError(e);
                                });
                        })
                        .catch((e) => {
                            setLoading(false);
                            handleError(e);
                        });
                })
                .catch(console.error);
        }
    }, [getter, poster, onAuthenticated]);

    useEffect(() => {
        authenticatePasskey();
    }, [authenticatePasskey]);

    return { isLoading };
};
