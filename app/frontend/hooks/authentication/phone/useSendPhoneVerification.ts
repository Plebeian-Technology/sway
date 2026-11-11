import { useHttp } from "@inertiajs/react";
import { notify } from "app/frontend/sway_utils";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { handleThrottledError } from "app/frontend/hooks/authentication/handleThrottledError";
import { useCallback } from "react";
import { sway } from "sway";

// @lat: [[phone-verification-confirm-put-method#Why useSendPhoneVerification uses useHttp instead of a page visit]]
export const useSendPhoneVerification = (onThrottled?: (until: Date | null) => void) => {
    const form = useHttp<{ phone_verification: { phone: string } }>({
        phone_verification: { phone: "" },
    });
    const { processing: isLoading } = form;

    const send = useCallback(
        async (phone: string): Promise<boolean | undefined> => {
            try {
                form.transform(() => ({ phone_verification: { phone } }));
                const result = (await form.post("/phone_verification")) as sway.IValidationResult | null | undefined;
                return result?.success;
            } catch (e) {
                if (handleThrottledError(e, "phone", onThrottled)) {
                    return undefined;
                }
                // @lat: [[phone-verification-confirm-put-method#Why useSendPhoneVerification uses useHttp instead of a page visit]]
                console.error("useSendPhoneVerification error:", e);
                notify({ level: "error", title: PARITY_COPY.auth.passkeyPanel.requestCodeError });
                return undefined;
            }
        },
        [form, onThrottled],
    );

    return { send, isLoading };
};
