import { useCallback, useMemo, useState } from "react";
import { sway } from "sway";

import { logDev, notify } from "app/frontend/sway_utils";
import { PHONE_INPUT_TRANSFORMER, removeNonDigits } from "app/frontend/sway_utils/phone";
import { Form as BootstrapForm, Button, Fade, Form } from "react-bootstrap";

import { Link as InertiaLink, router, usePage } from "@inertiajs/react";
import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import { useConfirmPhoneVerification } from "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification";
import { useSendPhoneVerification } from "app/frontend/hooks/authentication/phone/useSendPhoneVerification";
import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";
import { ROUTES } from "app/frontend/sway_constants";
import { AxiosError } from "axios";

interface ISigninValues {
    phone: string;
    code: string;
}

const INITIAL_VALUES: ISigninValues = {
    phone: "",
    code: "",
};

// https://docs.passwordless.dev/guide/frontend/react.html
// https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1
const Passkey: React.FC = () => {
    logDev("Passkey.tsx");
    const [phone, setPhone] = useState<string>(INITIAL_VALUES.phone);
    const [code, setCode] = useState<string>(INITIAL_VALUES.code);
    const errors = (usePage().props.errors ?? {}) as Record<string, any>;

    const onAuthenticated = useCallback((user: sway.IUser) => {
        if (!user) {
            logDev("Passkey.onAuthenticated - No user returned.");
            return;
        }

        if (user.isRegistrationComplete) {
            router.visit(ROUTES.legislators);
        } else {
            router.visit(ROUTES.registration);
        }
    }, []);

    const { send: sendPhoneVerification, isLoading: isLoadingSend } = useSendPhoneVerification();
    const { confirm: confirmPhoneVerification, isLoading: isLoadingConfirm } =
        useConfirmPhoneVerification(onAuthenticated);

    const {
        startAuthentication,
        verifyAuthentication,
        isLoading: isLoadingAuthentication,
    } = useWebAuthnAuthentication(onAuthenticated);

    const isLoading = useMemo(
        () => [isLoadingSend, isLoadingConfirm, isLoadingAuthentication].some(Boolean),
        [isLoadingSend, isLoadingConfirm, isLoadingAuthentication],
    );

    const [isConfirmingPhone, setConfirmingPhone] = useState<boolean>(false);

    const handleSubmit = useCallback(
        async (e: React.FormEvent) => {
            e.preventDefault();

            if (removeNonDigits(phone).length !== 10) {
                notify({ level: "warning", title: "Your phone number must be 10 digits." });
                return;
            }

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
                            setConfirmingPhone(publicKey);
                        } else if (!publicKey) {
                            return;
                        } else {
                            verifyAuthentication(phone, publicKey).catch(console.error);
                        }
                    })
                    .catch((error: AxiosError) => {
                        console.warn(e);
                        if (error.response?.status === 422) {
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
            code,
            isConfirmingPhone,
            confirmPhoneVerification,
            phone,
            startAuthentication,
            verifyAuthentication,
            sendPhoneVerification,
        ],
    );

    const handleCancel = useCallback((e: React.MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        e.stopPropagation();

        setConfirmingPhone(false);
    }, []);

    return (
        <div className="col fade-in-and-up">
            <div className="row">
                <div className="col">
                    <Form onSubmit={handleSubmit}>
                        <div className="row my-2">
                            <div className="col-lg-2 col-1">&nbsp;</div>
                            <div className="col-lg-8 col-10 px-0">
                                <h1 style={{ fontSize: "3em" }} className="fw-bold">
                                    Sway
                                </h1>
                                <h3 className="text-secondary my-3">Remember in November</h3>
                                <BootstrapForm.Group controlId="phone">
                                    <BootstrapForm.FloatingLabel label="Enter your phone number to get started.">
                                        <BootstrapForm.Control
                                            maxLength={16}
                                            type="tel"
                                            name="phone"
                                            autoComplete="tel webauthn"
                                            isInvalid={!!errors?.phone}
                                            value={PHONE_INPUT_TRANSFORMER.input(phone)}
                                            onChange={(e) => setPhone(PHONE_INPUT_TRANSFORMER.output(e))}
                                            disabled={isConfirmingPhone || isLoading}
                                        />
                                    </BootstrapForm.FloatingLabel>
                                </BootstrapForm.Group>
                                <span className="bold white" />
                            </div>
                        </div>
                        <Fade in={isConfirmingPhone} mountOnEnter unmountOnExit>
                            <div className="row my-2">
                                <div className="col-lg-2 col-1">&nbsp;</div>
                                <div className="col-lg-8 col-10 px-0">
                                    <BootstrapForm.Group controlId="code">
                                        <BootstrapForm.FloatingLabel label="Code:">
                                            <BootstrapForm.Control
                                                maxLength={6}
                                                type="text"
                                                name="code"
                                                autoComplete="one-time-code"
                                                isInvalid={!!errors?.code}
                                                onChange={(e) => setCode(e.target.value)}
                                                disabled={isLoading}
                                            />
                                        </BootstrapForm.FloatingLabel>
                                    </BootstrapForm.Group>
                                    <span className="bold white" />
                                </div>
                                <div className="col-lg-2 col-1">&nbsp;</div>
                            </div>
                        </Fade>
                        <div className="row mb-2">
                            <div className="col-lg-2 col-1">&nbsp;</div>
                            {isConfirmingPhone ? (
                                <div className="col ps-0">
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
                            ) : (
                                <div className="col px-0">
                                    <InertiaLink href={ROUTES.billOfTheWeek} className="btn btn-outline-primary w-100">
                                        Preview Sway
                                    </InertiaLink>
                                </div>
                            )}
                            <div className="col pe-0">
                                <Button className="w-100" variant="primary" type="submit" disabled={isLoading}>
                                    Submit
                                </Button>
                            </div>
                            <div className="col-lg-2 col-1">&nbsp;</div>
                        </div>
                        <div className="row d-none d-md-block">
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
