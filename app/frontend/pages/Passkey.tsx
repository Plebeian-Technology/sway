import { router } from "@inertiajs/react";
import { Client as PasswordlessClient } from "@passwordlessdev/passwordless-client";
import { useAxiosPost, useAxios_NOT_Authenticated_POST } from "app/frontend/hooks/useAxios";
import { setUser } from "app/frontend/redux/actions/userActions";
import { ROUTES } from "app/frontend/sway_constants";
import { useCallback, useMemo, useState } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";

import { ErrorMessage, Form, Formik } from "formik";
import { Form as BootstrapForm, Button } from "react-bootstrap";
import * as yup from "yup";
import { handleError } from "app/frontend/sway_utils";
import { usePasskeyAuthentication } from "app/frontend/hooks/authentication/usePasskeyAuthentication";

interface ISigninValues {
    email: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    email: yup.string().email("Invalid email address.").required("Email is required."),
});

const INITIAL_VALUES: ISigninValues = {
    email: "",
};

// https://docs.passwordless.dev/guide/frontend/react.html
// https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1
const Passkey: React.FC = () => {
    const dispatch = useDispatch();

    const { post: signupSwayPasskey } = useAxios_NOT_Authenticated_POST<{ token: string }>("/no_auth/passkeys/signup");
    const { post: signinSwayPasskey } = useAxios_NOT_Authenticated_POST<{
        user: sway.IUserWithSettingsAdmin;
        jwt: string;
    }>("/users/passkey/signin");

    const {
        post: login,
        items: authenticatedUser,
        isLoading: isLoadingLogin,
    } = useAxios_NOT_Authenticated_POST<sway.IUser>("/login");
    const {
        post: verifyEmail,
        items: authenticatedUserWithVerifiedEmail,
        isLoading: isLoadingVerifyEmail,
    } = useAxios_NOT_Authenticated_POST<sway.IUser>("/verify/email");
    const { post: verifyPhone, isLoading: isLoadingVerifyPhone } =
        useAxios_NOT_Authenticated_POST<sway.IUser>("/verify/phone");

    const handleSendEmailVerification = useCallback(() => {
        verifyEmail(authenticatedUser).catch(handleError);
    }, [verifyEmail, authenticatedUser]);

    const userAuthedNotEmailVerified = useMemo(
        () => !!authenticatedUser && !authenticatedUserWithVerifiedEmail,
        [authenticatedUser, authenticatedUserWithVerifiedEmail],
    );

    const disabled = useMemo(
        () => isLoadingLogin || isLoadingVerifyEmail || isLoadingVerifyPhone,
        [isLoadingLogin, isLoadingVerifyEmail, isLoadingVerifyPhone],
    );

    const onUserVerified = useCallback((verifiedUser: sway.IUserWithSettings) => {
        dispatch(setUser(verifiedUser.user));

        if (verifiedUser.user.user.isRegistrationComplete) {
            router.visit(ROUTES.legislators);
        } else {
            router.visit(ROUTES.registration);
        }
    }, [dispatch])

    const verifyUser = useCallback(
        async (token: string) => {
            const verifiedUser = await signinSwayPasskey({
                token,
                authenticity_token: (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content,
            }).catch(console.error);

            if (verifiedUser?.user?.user.id) {
                onUserVerified(verifiedUser.user)
            }
        },
        [onUserVerified, signinSwayPasskey],
    );

    const { isLoading: isLoadingPasskey } = usePasskeyAuthentication(onUserVerified);

    const handleSubmit = useCallback(
        async ({ email }: { email: string }) => {
            // In case of self-hosting PASSWORDLESS_API_URL will be different than https://v4.passwordless.dev
            const signedup = await signupSwayPasskey({
                email,
                authenticity_token: (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content,
            }).catch(console.error);
            if (!signedup) {
                return;
            }

            const { token: registerToken } = signedup;

            const passwordless = new PasswordlessClient({
                apiUrl: import.meta.env.VITE_BITWARDEN_PASSWORDLESS_API_URL,
                apiKey: import.meta.env.VITE_BITWARDEN_PASSWORDLESS_API_PUBLIC_KEY,
            });

            const { token, error } = await passwordless.register(registerToken, "sway");

            if (token) {
                await verifyUser(token);
            }

            if (error) {
                console.log(error);
            }
        },
        [signupSwayPasskey, verifyUser],
    );

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <Formik initialValues={INITIAL_VALUES} onSubmit={handleSubmit} validationSchema={VALIDATION_SCHEMA}>
                        {({ errors, handleChange, touched, handleBlur }) => {
                            return (
                                <Form>
                                    <div className="row my-2">
                                        <div className="col-lg-4 col-1">&nbsp;</div>
                                        <div className="col-lg-4 col-10">
                                            <BootstrapForm.Group controlId="email">
                                                <BootstrapForm.Control
                                                    disabled={disabled}
                                                    type="email"
                                                    name="email"
                                                    placeholder="Email"
                                                    autoComplete="email webauthn"
                                                    isInvalid={Boolean(touched.email && errors.email)}
                                                    onBlur={handleBlur}
                                                    onChange={handleChange}
                                                />
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
                            );
                        }}
                    </Formik>
                </div>
            </div>
        </div>
    );
};

export default Passkey;
