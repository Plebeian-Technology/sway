import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { logDev, notify } from "app/frontend/sway_utils";
import { router, useHttp } from "@inertiajs/react";
import { useCallback, useState } from "react";

// @lat: [[passkey-management-page-overview#Removing a passkey#The web remove flow]]
const VERIFY_PHONE_ROUTE = "/users/passkeys/verify_phone";
const CONFIRM_PHONE_ROUTE = "/users/passkeys/confirm_phone";
const passkeyRoute = (id: number) => `/users/passkeys/${id}`;

export type RemovePasskeyStep = "idle" | "awaiting_code" | "working";

export interface IRemovablePasskey {
    id: number;
    label: string | null;
}

export const useRemovePasskey = () => {
    const http = useHttp<Record<string, any>>({});
    const confirm = useConfirm();
    const [step, setStep] = useState<RemovePasskeyStep>("idle");
    const [target, setTarget] = useState<IRemovablePasskey | null>(null);

    const reset = useCallback(() => {
        setTarget(null);
        setStep("idle");
    }, []);

    const begin = useCallback(
        async (passkey: IRemovablePasskey) => {
            setTarget(passkey);
            setStep("working");
            try {
                http.transform(() => ({}));
                const res = (await http.post(VERIFY_PHONE_ROUTE)) as { success?: boolean } | null;
                if (res?.success) {
                    setStep("awaiting_code");
                    return;
                }
            } catch (e) {
                logDev("useRemovePasskey.begin failed", e);
            }
            notify({ level: "error", title: PARITY_COPY.passkey.removeError });
            reset();
        },
        [http, reset],
    );

    const submit = useCallback(
        async (code: string) => {
            if (!target) return;

            setStep("working");
            try {
                http.transform(() => ({ code }));
                const confirmed = (await http.post(CONFIRM_PHONE_ROUTE)) as { success?: boolean } | null;
                if (!confirmed?.success) {
                    notify({ level: "error", title: PARITY_COPY.passkey.codeError });
                    setStep("awaiting_code");
                    return;
                }

                const label = target.label ?? "Passkey";
                const accepted = await confirm({
                    title: PARITY_COPY.passkey.removeConfirmTitle,
                    description: PARITY_COPY.passkey.removeConfirmBody(label),
                    confirmLabel: PARITY_COPY.passkey.removeCta,
                    tone: "destructive",
                });
                if (!accepted) {
                    reset();
                    return;
                }

                http.transform(() => ({}));
                const result = (await http.delete(passkeyRoute(target.id))) as {
                    success?: boolean;
                    message?: string;
                } | null;
                if (result?.success) {
                    notify({ level: "success", title: PARITY_COPY.passkey.removeSuccess });
                    router.reload({ only: ["passkeys"] });
                } else {
                    notify({ level: "error", title: result?.message ?? PARITY_COPY.passkey.removeError });
                }
            } catch (e) {
                logDev("useRemovePasskey.submit failed", e);
                notify({ level: "error", title: PARITY_COPY.passkey.removeError });
            }
            reset();
        },
        [confirm, http, reset, target],
    );

    return { step, target, begin, submit, cancel: reset } as const;
};
