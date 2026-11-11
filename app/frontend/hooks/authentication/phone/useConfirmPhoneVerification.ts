import { useHttp } from "@inertiajs/react";
import { useWebAuthnRegistration } from "app/frontend/hooks/authentication/useWebAuthnRegistration";
import { handleError, notify } from "app/frontend/sway_utils";
import { handleThrottledError } from "app/frontend/hooks/authentication/handleThrottledError";
import { trackFunnelStep } from "app/frontend/sway_utils/funnelTracker";
import { useCallback } from "react";

type ConfirmPhoneVerificationResponse = {
    success: boolean;
    error?: string;
};

// @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
export const useConfirmPhoneVerification = (onThrottled?: (until: Date | null) => void) => {
    const { startRegistration, verifyRegistration, isLoading: isRegistering } = useWebAuthnRegistration(onThrottled);
    const form = useHttp<{ phone_verification: { phone: string; code: string } }>({
        phone_verification: { phone: "", code: "" },
    });
    const { processing: isLoading } = form;

    const confirm = useCallback(
        async (phone: string, code: string): Promise<void> => {
            try {
                form.transform(() => ({ phone_verification: { phone, code } }));
                const result = (await form.put("/phone_verification/0")) as
                    | ConfirmPhoneVerificationResponse
                    | null
                    | undefined;

                if (result?.success) {
                    trackFunnelStep("sms_verified");
                    try {
                        const publicKey = await startRegistration(phone);
                        if (publicKey) {
                            await verifyRegistration(phone, publicKey);
                        }
                    } catch (e) {
                        handleError(e as Error);
                    }
                } else {
                    trackFunnelStep("sms_verification_failed", { reason: "incorrect_code" });
                    // @lat: [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]]
                    notify({ level: "error", title: result?.error || "Incorrect Code" });
                }
            } catch (e) {
                if (handleThrottledError(e, "phone", onThrottled)) {
                    return;
                }
                handleError(e as Error);
            }
        },
        [form, startRegistration, verifyRegistration, onThrottled],
    );

    return { confirm, isLoading: isLoading || isRegistering };
};
