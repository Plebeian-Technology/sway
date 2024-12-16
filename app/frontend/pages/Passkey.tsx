import { useCallback, useEffect, useMemo, useState } from "react";
import { sway } from "sway";

import { logDev, notify, SWAY_STORAGE } from "app/frontend/sway_utils";
import { isValidPhoneNumber, PHONE_INPUT_TRANSFORMER, removeNonDigits } from "app/frontend/sway_utils/phone";
import { Button, Fade, Form } from "react-bootstrap";

import { PublicKeyCredentialWithAssertionJSON } from "@github/webauthn-json";
import { useForm } from "@inertiajs/react";
import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import { useConfirmPhoneVerification } from "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification";
import { useSendPhoneVerification } from "app/frontend/hooks/authentication/phone/useSendPhoneVerification";
import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";
import { AxiosError } from "axios";
import * as yup from "yup";
import { noop } from "lodash";

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

const onAuthenticated = async (user: sway.IUser) => {
    if (!user) {
        logDev("Passkey.onAuthenticated - No user returned.");
        return;
    } else {
        logDev("Passkey.onAuthenticated - Storing phone.");
    }
    localStorage.setItem(SWAY_STORAGE.Local.User.Phone, removeNonDigits(user.phone));
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

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <Form onSubmit={handleSubmit}>
                        <div className="row my-2">
                            <div className="col-lg-4 col-1">&nbsp;</div>
                            <div className="col-lg-4 col-10">
                                <Form.Group controlId="phone">
                                    <Form.FloatingLabel label="Please enter your phone number...">
                                        <Form.Control
                                            maxLength={16}
                                            type="tel"
                                            name="phone"
                                            autoComplete="tel webauthn"
                                            isInvalid={!!errors.phone}
                                            value={PHONE_INPUT_TRANSFORMER.input(data.phone)}
                                            disabled={isConfirmingPhone || isLoading}
                                            onChange={(e) => setData("phone", e.target.value)}
                                        />
                                    </Form.FloatingLabel>
                                </Form.Group>
                                {errors.phone && <span className="text-white">{errors.phone}</span>}
                            </div>
                        </div>
                        <Fade in={isConfirmingPhone} mountOnEnter unmountOnExit>
                            <div className="row my-2">
                                <div className="col-lg-4 col-1">&nbsp;</div>
                                <div className="col-lg-4 col-10">
                                    <Form.Group controlId="code">
                                        <Form.FloatingLabel label="Code:">
                                            <Form.Control
                                                maxLength={6}
                                                type="text"
                                                name="code"
                                                autoComplete="one-time-code"
                                                isInvalid={!!errors.code}
                                                disabled={isLoading}
                                                onChange={(e) => setData("code", e.target.value)}
                                            />
                                        </Form.FloatingLabel>
                                    </Form.Group>
                                    {errors.code && <span className="text-white">{errors.code}</span>}
                                </div>
                                <div className="col-lg-4 col-1">&nbsp;</div>
                            </div>
                        </Fade>
                        <div className="row my-2">
                            <div className="col-lg-4 col-1">&nbsp;</div>
                            <div className="col">
                                <Fade in={isConfirmingPhone}>
                                    <Button
                                        className="w-100"
                                        variant="outline-light"
                                        disabled={isLoading}
                                        onClick={handleCancel}
                                    >
                                        Cancel
                                    </Button>
                                </Fade>
                            </div>
                            <div className="col">
                                <Button className="w-100" variant="primary" type="submit" disabled={isLoading}>
                                    Submit
                                </Button>
                            </div>
                            <div className="col-lg-4 col-1">&nbsp;</div>
                        </div>
                        <div className="row">
                            <div className="col text-center">
                                <CenteredLoading className="white" isHidden={!isLoading} />
                            </div>
                        </div>
                    </Form>
                </div>
            </div>
        </div>
    );
};

export default Passkey;
