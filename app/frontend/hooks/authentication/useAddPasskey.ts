import { router, useHttp } from "@inertiajs/react";
import { create, logDev, notify, PublicKeyCredentialCreationOptionsJSON } from "app/frontend/sway_utils";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { useCallback, useState } from "react";

// @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
const VERIFY_PHONE_ROUTE = "/users/passkeys/verify_phone";
const CONFIRM_PHONE_ROUTE = "/users/passkeys/confirm_phone";
const ADD_OPTIONS_ROUTE = "/users/passkeys/add_options";
const ADD_CALLBACK_ROUTE = "/users/passkeys/add_callback";

export type AddPasskeyStep = "idle" | "awaiting_code" | "working";

export const useAddPasskey = () => {
    const http = useHttp<Record<string, any>>({});
    const [step, setStep] = useState<AddPasskeyStep>("idle");

    const begin = useCallback(async () => {
        setStep("working");
        try {
            http.transform(() => ({}));
            const res = (await http.post(VERIFY_PHONE_ROUTE)) as { success?: boolean } | null;
            if (res?.success) {
                setStep("awaiting_code");
            } else {
                notify({ level: "error", title: PARITY_COPY.passkey.addError });
                setStep("idle");
            }
        } catch (e) {
            logDev("useAddPasskey.begin failed", e);
            notify({ level: "error", title: PARITY_COPY.passkey.addError });
            setStep("idle");
        }
    }, [http]);

    const cancel = useCallback(() => setStep("idle"), []);

    const submit = useCallback(
        async (code: string, label: string) => {
            setStep("working");
            try {
                http.transform(() => ({ code }));
                const confirmed = (await http.post(CONFIRM_PHONE_ROUTE)) as { success?: boolean } | null;
                if (!confirmed?.success) {
                    notify({ level: "error", title: PARITY_COPY.passkey.codeError });
                    setStep("awaiting_code");
                    return;
                }

                http.transform(() => ({}));
                const options = (await http.post(ADD_OPTIONS_ROUTE)) as
                    | (PublicKeyCredentialCreationOptionsJSON & { success?: undefined })
                    | { success: false; message?: string };
                if ("success" in options && options.success === false) {
                    notify({ level: "error", title: options.message ?? PARITY_COPY.passkey.addError });
                    setStep("awaiting_code");
                    return;
                }

                const publicKeyCredential = await create({
                    publicKey: options as PublicKeyCredentialCreationOptionsJSON,
                });

                http.transform(() => ({ publicKeyCredential, passkey_label: label }));
                const result = (await http.post(ADD_CALLBACK_ROUTE)) as { success?: boolean; message?: string } | null;
                if (result?.success) {
                    notify({ level: "success", title: PARITY_COPY.passkey.addSuccess });
                    setStep("idle");
                    router.reload({ only: ["passkeys"] });
                } else {
                    notify({ level: "error", title: result?.message ?? PARITY_COPY.passkey.addError });
                    setStep("awaiting_code");
                }
            } catch (e) {
                logDev("useAddPasskey.submit failed", e);
                notify({ level: "error", title: PARITY_COPY.passkey.addError });
                setStep("awaiting_code");
            }
        },
        [http],
    );

    return { step, begin, submit, cancel } as const;
};
