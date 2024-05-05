import { useCallback, useState } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";

import { setUser } from "app/frontend/redux/actions/userActions";
import { logDev, notify } from "app/frontend/sway_utils";
import { PHONE_INPUT_TRANSFORMER, isValidPhoneNumber } from "app/frontend/sway_utils/phone";
import { ErrorMessage, Field, FieldAttributes, Form, Formik, FormikProps } from "formik";
import { Form as BootstrapForm, Button } from "react-bootstrap";

import { useConfirmPhoneVerification } from "app/frontend/hooks/authentication/phone/useConfirmPhoneVerification";
import { useSendPhoneVerification } from "app/frontend/hooks/authentication/phone/useSendPhoneVerification";
import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";
import { AxiosError } from "axios";
import { Animate } from "react-simple-animate";
import * as yup from "yup";

interface ISigninValues {
    phone: string;
    code: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    phone: yup
        .string()
        .required("Phone is required.")
        .test("Is valid phone number", "Please enter a valid phone number.", (value) => isValidPhoneNumber(value)),
    code: yup.string().max(6)
});

const INITIAL_VALUES: ISigninValues = {
    phone: "",
    code: ""
};

// https://docs.passwordless.dev/guide/frontend/react.html
// https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1
const Passkey: React.FC = () => {
    logDev("Passkey.tsx");

    const dispatch = useDispatch();

    const onAuthenticated = useCallback(
        (user: sway.IUser) => {
            logDev("onAuthenticated", user);
            if (!user) return;

            dispatch(setUser(user));

            // if (user.isRegistrationComplete) {
            //     router.visit(ROUTES.legislators);
            // } else {
            //     router.visit(ROUTES.registration);
            // }
        },
        [dispatch],
    );

    const { send: sendPhoneVerification, isLoading: isLoadingSend } = useSendPhoneVerification();
    const { confirm: confirmPhoneVerification, isLoading: isLoadingConfirm } =
        useConfirmPhoneVerification(onAuthenticated);

    const { startAuthentication, verifyAuthentication } = useWebAuthnAuthentication(onAuthenticated);

    const [isConfirmingPhone, setConfirmingPhone] = useState<boolean>(false);

    const handleSubmit = useCallback(
        async ({ phone, code }: { phone: string; code?: string }) => {
            
            if (code && isConfirmingPhone) {
                confirmPhoneVerification(phone, code);
            } else {
                startAuthentication(phone)
                    .then((publicKey) => {
                        if (typeof publicKey === "boolean") {
                            if (!publicKey) {
                                notify({
                                    level: "error",
                                    title: "Please enter a valid phone number."
                                })
                            }
                            setConfirmingPhone(publicKey)
                        } 
                        else if (!publicKey) {
                            return;
                        } else {
                            verifyAuthentication(phone, publicKey).catch(console.error);
                        }
                    })
                    .catch((e: AxiosError) => {
                        console.warn(e)
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
        [confirmPhoneVerification, isConfirmingPhone, sendPhoneVerification, startAuthentication, verifyAuthentication],
    );

    const handleCancel = useCallback((e: React.MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        e.stopPropagation();

        setConfirmingPhone(false);
    }, []);

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <Formik initialValues={INITIAL_VALUES} onSubmit={handleSubmit} validationSchema={VALIDATION_SCHEMA}>
                        {(_props: FormikProps<any>) => (
                            <Form>
                                <div className="row my-2">
                                    <div className="col-lg-4 col-1">&nbsp;</div>
                                    <div className="col-lg-4 col-10">
                                        <BootstrapForm.Group controlId="phone">
                                            <Field name="phone">
                                                {({ field, form: { touched, errors } }: FieldAttributes<any>) => (
                                                    <BootstrapForm.FloatingLabel label="Please enter your phone number:">
                                                        <BootstrapForm.Control
                                                            {...field}
                                                            type="tel"
                                                            name="phone"
                                                            autoComplete="tel webauthn"
                                                            isInvalid={Boolean(touched.phone && errors.phone)}
                                                            value={PHONE_INPUT_TRANSFORMER.input(field.value)}
                                                            disabled={
                                                                isConfirmingPhone || isLoadingSend || isLoadingConfirm
                                                            }
                                                        />
                                                    </BootstrapForm.FloatingLabel>
                                                )}
                                            </Field>
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"phone"} className="bold white" />
                                    </div>
                                    <div className="col-lg-4 col-1">&nbsp;</div>
                                </div>
                                <Animate
                                    play={isConfirmingPhone}
                                    start={{ opacity: 0, display: "none" }}
                                    end={{ display: "initial", opacity: 1 }}
                                >
                                    <div className="row my-2">
                                        <div className="col-lg-4 col-1">&nbsp;</div>
                                        <div className="col-lg-4 col-10">
                                            <BootstrapForm.Group controlId="code">
                                                <Field name="code">
                                                    {({ field, form: { touched, errors } }: FieldAttributes<any>) => (
                                                        <BootstrapForm.FloatingLabel label="Code:">
                                                            <BootstrapForm.Control
                                                                {...field}
                                                                type="number"
                                                                name="code"
                                                                autoComplete="one-time-code"
                                                                isInvalid={Boolean(touched.code && errors.code)}
                                                                disabled={isLoadingSend || isLoadingConfirm}
                                                            />
                                                        </BootstrapForm.FloatingLabel>
                                                    )}
                                                </Field>
                                            </BootstrapForm.Group>
                                            <ErrorMessage name={"code"} className="bold white" />
                                        </div>
                                        <div className="col-lg-4 col-1">&nbsp;</div>
                                    </div>
                                </Animate>
                                <div className="row my-2">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col">
                                        <Animate play={isConfirmingPhone} start={{ opacity: 0 }} end={{ opacity: 1 }}>
                                            <Button
                                                className="w-100"
                                                variant="outline-light"
                                                disabled={isLoadingSend || isLoadingConfirm}
                                                onClick={handleCancel}
                                            >
                                                Cancel
                                            </Button>
                                        </Animate>
                                    </div>
                                    <div className="col">
                                        <Button
                                            className="w-100"
                                            variant="primary"
                                            type="submit"
                                            disabled={isLoadingSend || isLoadingConfirm}
                                        >
                                            Submit
                                        </Button>
                                    </div>
                                    <div className="col-1">&nbsp;</div>
                                </div>
                            </Form>
                        )}
                    </Formik>
                </div>
            </div>
        </div>
    );
};

export default Passkey;
