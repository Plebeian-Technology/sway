import * as webauthnJson from "@github/webauthn-json";
import { useCallback, useEffect, useMemo, useState } from "react";
import { sway } from "sway";

import { handleError, logDev, notify, SWAY_STORAGE } from "app/frontend/sway_utils";
import { isValidPhoneNumber, removeNonDigits } from "app/frontend/sway_utils/phone";
import { Button, Fade } from "react-bootstrap";

import { PublicKeyCredentialWithAssertionJSON } from "@github/webauthn-json";
import { router, useForm, usePage } from "@inertiajs/react";
import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import CodeForm from "app/frontend/components/forms/phone/CodeForm";
import PhoneForm from "app/frontend/components/forms/phone/PhoneForm";
import { useConfirmPhoneVerification } from "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification";
import { useSendPhoneVerification } from "app/frontend/hooks/authentication/phone/useSendPhoneVerification";
import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";
import { AxiosError } from "axios";
import { noop } from "lodash";
import * as yup from "yup";
import PhoneConfirmationForm from "app/frontend/components/forms/phone/PhoneConfirmationForm";

interface ISigninValues {
    phone: string;
    code: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    phone: yup
        .string()
        .required("Phone is required.")
        .test("Is valid phone number", "Please enter a valid phone number.", (value) => isValidPhoneNumber(value)),
    code: yup.string().max(6),
});

const INITIAL_VALUES: ISigninValues = {
    phone: "",
    code: "",
};

interface IAuthentication extends sway.IUser {
    publicKeyCredential?: PublicKeyCredentialWithAssertionJSON;
    code?: string;
}

const onAuthenticated = async (user: sway.IUser & { route?: string }) => {
    if (!user) {
        logDev("Passkey.onAuthenticated - No user returned.");
        return;
    } else {
        logDev("Passkey.onAuthenticated - Storing phone.");
    }
    localStorage.setItem(SWAY_STORAGE.Local.User.Phone, removeNonDigits(user.phone));

    if (user.route) {
        router.visit(user.route);
    }
};

// https://docs.passwordless.dev/guide/frontend/react.html
// https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1
const Passkey: React.FC = () => {
    logDev("Passkey.tsx");
    const storedPhone = localStorage.getItem(SWAY_STORAGE.Local.User.Phone);
    const defaults = useMemo(
        () => ({
            ...INITIAL_VALUES,
            phone: storedPhone || "",
        }),
        [storedPhone],
    );

    const { data, setData, errors, setError, post, transform, processing } = useForm<IAuthentication>(
        "Login",
        defaults as IAuthentication,
    );

    const { send: sendPhoneVerification, isLoading: isLoadingSend } = useSendPhoneVerification();
    const { confirm: confirmPhoneVerification, isLoading: isLoadingConfirm } =
        useConfirmPhoneVerification(onAuthenticated);

    const {
        startAuthentication,
        verifyAuthentication,
        isLoading: isLoadingAuthentication,
    } = useWebAuthnAuthentication(post, transform, onAuthenticated);

    const isLoading = useMemo(
        () => [isLoadingSend, isLoadingConfirm, isLoadingAuthentication].some(Boolean),
        [isLoadingSend, isLoadingConfirm, isLoadingAuthentication],
    );

    const [isConfirmingPhone, setConfirmingPhone] = useState<boolean>(false);

    const handleSubmit = useCallback(
        async (event: React.FormEvent) => {
            event.preventDefault();

            const codeError = await VALIDATION_SCHEMA.validateAt("code", data)
                .then(noop)
                .catch((e: yup.ValidationError) => e.message);
            const phoneError = await VALIDATION_SCHEMA.validateAt("phone", data)
                .then(noop)
                .catch((e: yup.ValidationError) => e.message);

            if (codeError || phoneError) {
                if (codeError) {
                    setError("code", codeError);
                }
                if (phoneError) {
                    setError("phone", phoneError);
                }
                return;
            }

            const { phone, code } = data;

            if (code && isConfirmingPhone) {
                confirmPhoneVerification(phone, code);
            } else {
                return startAuthentication(phone)
                    .then((publicKey) => {
                        if (typeof publicKey === "boolean") {
                            if (!publicKey) {
                                notify({
                                    level: "error",
                                    title: "Please enter a valid phone number.",
                                });
                            }
                            logDev("handleSubmit - confirm phone");
                            setConfirmingPhone(publicKey);
                        } else if (!publicKey) {
                            logDev("handleSubmit - no publicKey");
                            return;
                        } else {
                            logDev("handleSubmit.verifyAuthentication");
                            // verifyAuthentication(phone, publicKey)
                            setData({ phone, publicKeyCredential: publicKey } as IAuthentication);
                        }
                    })
                    .catch((e: AxiosError) => {
                        console.warn(e);
                        if (e.response?.status === 422) {
                            sendPhoneVerification(phone)
                                .then((success) => {
                                    setConfirmingPhone(!!success);
                                })
                                .catch(console.error);
                        }
                    });
            }
        },
        [
            data,
            isConfirmingPhone,
            setError,
            confirmPhoneVerification,
            startAuthentication,
            setData,
            sendPhoneVerification,
        ],
    );

    const handleCancel = useCallback((e: React.MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        e.stopPropagation();

        setConfirmingPhone(false);
    }, []);

    useEffect(() => {
        if (!processing && data.phone && data.publicKeyCredential) {
            logDev("verify auth");
            verifyAuthentication(data.phone, data.publicKeyCredential);
        }
    }, [data.phone, data.publicKeyCredential, processing, verifyAuthentication]);

    const params = usePage().props.params as Record<string, any>;
    useEffect(() => {
        // const props = new URLSearchParams(window.location.search)
        if (params?.authenticatorSelection?.userVerification === "required") {
            webauthnJson.get({ publicKey: params } as webauthnJson.CredentialRequestOptionsJSON).catch((e: Error) => {
                if (e.name === "AbortError") {
                    // noop
                } else {
                    handleError(e);
                }
            });
        }
    }, [params]);

    return (
        <div className="col">
            <div className="row">
                <PhoneConfirmationForm />
            </div>
        </div>
    );
};

export default Passkey;
