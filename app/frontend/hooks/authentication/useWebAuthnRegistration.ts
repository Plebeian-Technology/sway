import { clearIdentityCaches, IDENTITY_CHANGE_RETRY, prepareIdentityChange } from "./prepareIdentityChange";
import { HttpResponseError } from "@inertiajs/core";
import { router, useHttp } from "@inertiajs/react";
import {
    create,
    handleError,
    notify,
    PublicKeyCredentialCreationOptionsJSON,
    PublicKeyCredentialWithAttestationJSON,
} from "app/frontend/sway_utils";
import { handleThrottledError } from "app/frontend/hooks/authentication/handleThrottledError";
import { trackFunnelStep } from "app/frontend/sway_utils/funnelTracker";
import { useCallback, useState } from "react";

const REGISTRATION_ROUTE = "/users/webauthn/registration";
const CALLBACK_ROUTE = "/users/webauthn/registration/callback";

export const useWebAuthnRegistration = (onThrottled?: (until: Date | null) => void) => {
    const http = useHttp<Record<string, any>>({});
    const [isLoading, setLoading] = useState<boolean>(false);

    const startRegistration = useCallback(
        async (phone: string) => {
            const controller = new AbortController();

            setLoading(true);
            try {
                http.transform(() => ({ phone, passkey_label: "Sway" }));
                const result = (await http.post(REGISTRATION_ROUTE)) as PublicKeyCredentialCreationOptionsJSON;

                if (result) {
                    trackFunnelStep("passkey_prompt_shown");
                    return create({ publicKey: result, signal: controller.signal })
                        .then((cred) => {
                            trackFunnelStep("passkey_prompt_accepted");
                            return cred;
                        })
                        .catch((e) => {
                            setLoading(false);
                            trackFunnelStep("passkey_prompt_dismissed", {
                                error_name: e?.name || "UnknownError",
                            });
                            handleError(e);
                        });
                } else {
                    setLoading(false);
                }
            } catch (e) {
                setLoading(false);
                if (handleThrottledError(e, "sign_up", onThrottled)) {
                    return;
                }
                // @lat: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]
                if (e instanceof HttpResponseError && e.response.status === 409) {
                    notify({
                        level: "error",
                        title: "This phone already has a Sway account. Sign in with your passkey, or contact Sway support if you've lost access.",
                    });
                    return;
                }
                handleError(e as Error);
            }
        },
        [http, onThrottled],
    );

    const verifyRegistration = useCallback(
        async (phone: string, publicKeyCredential: PublicKeyCredentialWithAttestationJSON) => {
            if (!phone || !publicKeyCredential) {
                setLoading(false);
                return;
            }

            // @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
            setLoading(true);
            try {
                await prepareIdentityChange();
            } catch {
                setLoading(false);
                notify({ level: "error", title: IDENTITY_CHANGE_RETRY });
                return;
            }

            router.post(CALLBACK_ROUTE, { phone, passkey_label: "Sway", ...publicKeyCredential } as any, {
                preserveState: false,
                onBeforeUpdate: clearIdentityCaches,
                onSuccess: () => {
                    trackFunnelStep("passkey_enrolled");
                },
                onError: (errors) => {
                    trackFunnelStep("passkey_enrollment_failed", { errors });
                },
                onFinish: () => setLoading(false),
            });
        },
        [],
    );

    return {
        startRegistration,
        verifyRegistration,
        isLoading,
    };
};
