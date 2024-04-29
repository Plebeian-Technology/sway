import { useCallback } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";

import { useWebAuthnRegistration } from "app/frontend/hooks/authentication/useWebAuthnRegistration";
import { setUser } from "app/frontend/redux/actions/userActions";
import { ROUTES } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";
import { PHONE_INPUT_TRANSFORMER, isValidPhoneNumber } from "app/frontend/sway_utils/phone";
import { ErrorMessage, Field, FieldAttributes, Form, Formik, FormikProps } from "formik";
import { Form as BootstrapForm, Button } from "react-bootstrap";

import { router } from "@inertiajs/react";
import { useWebAuthnAuthentication } from "app/frontend/hooks/authentication/useWebAuthnAuthentication";
import { AxiosError } from "axios";
import * as yup from "yup";

interface ISigninValues {
    phone: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    phone: yup
        .string()
        .required("Phone is required.")
        .test("Is valid phone number", (value) => isValidPhoneNumber(value)),
});

const INITIAL_VALUES: ISigninValues = {
    phone: "",
};

// https://docs.passwordless.dev/guide/frontend/react.html
// https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1
const Passkey: React.FC = () => {
    logDev("Passkey.tsx");

    const dispatch = useDispatch();

    const onAuthenticated = useCallback(
        (user: sway.IUserWithSettingsAdmin) => {
            logDev("onAuthenticated", user);
            if (!user) return;

            dispatch(setUser(user));

            if (user.isRegistrationComplete) {
                router.visit(ROUTES.legislators);
            } else {
                router.visit(ROUTES.registration);
            }
        },
        [dispatch],
    );

    const { startRegistration, verifyRegistration } = useWebAuthnRegistration(onAuthenticated);
    const { startAuthentication, verifyAuthentication } = useWebAuthnAuthentication(onAuthenticated);

    const handleSubmit = useCallback(
        async ({ phone }: { phone: string }) => {
            // In case of self-hosting PASSWORDLESS_API_URL will be different than https://v4.passwordless.dev
            startAuthentication(phone)
                .then((publicKey) => {
                    if (!publicKey) {
                        return;
                    } else {
                        verifyAuthentication(phone, publicKey).catch(console.error)
                    }
                })
                .catch((e: AxiosError) => {
                    if (e.response?.status === 422) {
                        startRegistration(phone)
                            .then(async (publicKey) => {
                                if (!publicKey) {
                                    return;
                                }

                                await verifyRegistration(phone, publicKey).then((result) => {
                                    if (result) {
                                        window.location.reload();
                                    }
                                });
                            })
                            .catch(console.error);
                    }
                });
        },
        [startAuthentication, startRegistration, verifyAuthentication, verifyRegistration],
    );

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
                                                        />
                                                    </BootstrapForm.FloatingLabel>
                                                )}
                                            </Field>
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"phone"} className="bold white" />
                                    </div>
                                    <div className="col-lg-4 col-1">&nbsp;</div>
                                </div>
                                <div className="row my-2">
                                    <div className="col">
                                        <Button variant="primary" type="submit">
                                            Submit
                                        </Button>
                                    </div>
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
