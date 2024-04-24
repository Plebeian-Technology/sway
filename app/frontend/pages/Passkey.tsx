import { useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { useCallback, useMemo } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";

import { usePasskeyAuthentication } from "app/frontend/hooks/authentication/usePasskeyAuthentication";
import { useWebAuthnRegistration } from "app/frontend/hooks/authentication/useWebAuthnRegistration";
import { setUser } from "app/frontend/redux/actions/userActions";
import { ROUTES } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";
import { PHONE_INPUT_TRANSFORMER } from "app/frontend/sway_utils/phone";
import { ErrorMessage, Field, FieldAttributes, Form, Formik, FormikProps } from "formik";
import { Form as BootstrapForm, Button } from "react-bootstrap";

import { router } from "@inertiajs/react";
import * as yup from "yup";

interface ISigninValues {
    email: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    email: yup.string().email().required("Email is required."),
});

const INITIAL_VALUES: ISigninValues = {
    email: "",
};

// https://docs.passwordless.dev/guide/frontend/react.html
// https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1
const Passkey: React.FC = () => {
    logDev("Passkey.tsx")

    const dispatch = useDispatch();

    const {
        // items: authenticatedUser,
        isLoading: isLoadingLogin,
    } = useAxios_NOT_Authenticated_POST<sway.IUser>("/login");

    // const {
    //     post: verifyEmail,
    //     items: authenticatedUserWithVerifiedEmail,
    //     isLoading: isLoadingVerifyEmail,
    // } = useAxios_NOT_Authenticated_POST<sway.IUser>("/verify/phone");

    // const { post: verifyPhone, items: authenticatedUserWithVerifiedPhone, isLoading: isLoadingVerifyPhone } =
    //     useAxios_NOT_Authenticated_POST<sway.IUser>("/verify/phone");

    // const handleSendPhoneVerification = useCallback(() => {
    //     verifyPhone(authenticatedUser).catch(handleError);
    // }, [verifyPhone, authenticatedUser]);

    // const userAuthedNotPhoneVerified = useMemo(
    //     () => !!authenticatedUser && !authenticatedUserWithVerifiedPhone,
    //     [authenticatedUser, authenticatedUserWithVerifiedPhone],
    // );

    const onAuthenticated = useCallback((user: sway.IUserWithSettingsAdmin) => {
        logDev("onAuthenticated", user)
        if (!user) return;

        dispatch(setUser(user));

        if (user.isRegistrationComplete) {
            router.visit(ROUTES.legislators)
        } else {
            router.visit(ROUTES.registration)
        }
    }, [dispatch])

    const { startRegistration, verifyRegistration } = useWebAuthnRegistration(onAuthenticated);

    // usePasskeyAuthentication(onAuthenticated)

    const disabled = useMemo(
        () => isLoadingLogin,
        [isLoadingLogin],
    );

    const handleSubmit = useCallback(
        async ({ email }: { email: string }) => {
            // In case of self-hosting PASSWORDLESS_API_URL will be different than https://v4.passwordless.dev
            const publicKey = await startRegistration(email).catch(console.error);
            if (!publicKey) {
                return;
            }

            if (publicKey) {
                await verifyRegistration(email, publicKey).then((result) => {
                    if (result?.success) {
                        window.location.reload();
                    }
                });
            }
        },
        [startRegistration, verifyRegistration],
    );

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <Formik
                        initialValues={INITIAL_VALUES}
                        onSubmit={handleSubmit}
                        validationSchema={VALIDATION_SCHEMA}
                    >
                        {(_props: FormikProps<any>) => (
                            <Form>
                                <div className="row my-2">
                                    <div className="col-lg-4 col-1">&nbsp;</div>
                                    <div className="col-lg-4 col-10">
                                        <BootstrapForm.Group controlId="email">
                                            <Field name="email">
                                                {({
                                                    field,
                                                    form: { touched, errors },
                                                }: FieldAttributes<any>) => (
                                                    <BootstrapForm.FloatingLabel label="Please enter your email:">
                                                    <BootstrapForm.Control
                                                        {...field}
                                                        disabled={disabled}
                                                        type="tel"
                                                        name="email"
                                                        placeholder="Email..."
                                                        autoComplete="username webauthn"
                                                        isInvalid={Boolean(
                                                            touched.email && errors.email,
                                                        )}
                                                    />
                                                    </BootstrapForm.FloatingLabel>
                                                )}
                                            </Field>
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"email"} className="bold white" />
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
