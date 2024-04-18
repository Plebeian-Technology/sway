/** @format */

// import { router, Link as InertiaLink } from "@inertiajs/react";
import { Link as InertiaLink } from '@inertiajs/inertia-react';
import { ErrorMessage, Form, Formik } from "formik";
import { useCallback, useMemo } from "react";
import { Form as BootstrapForm, Button } from "react-bootstrap";
import * as yup from "yup";

import { sway } from "sway";

import { useAxios_NOT_Authenticated_POST } from "../../hooks/useAxios";
import { IS_MOBILE_PHONE, ROUTES } from "../../sway_constants";
import { useLogout } from "../../hooks/users/useLogout";
import { handleError } from "../../sway_utils";

interface ISigninValues {
    email: string;
    password: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    email: yup.string().email("Invalid email address.").required("Email is required."),
    password: yup.string().required("Password is required."),
});

const INITIAL_VALUES: ISigninValues = {
    email: "",
    password: "",
};

interface IProps {}

const LoginForm: React.FC<IProps> = () => {
    const logout = useLogout();

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

    // useEffect(() => {
    //     logDev("Login.useEffect.needsActivationQS", search);
    //     const needsActivationQS: string | null = new URLSearchParams(search).get(
    //         "needsEmailActivation",
    //     );
    //     if (needsActivationQS === "1") {
    //         notify({
    //             level: "info",
    //             title: "Please verify your email.",
    //         });
    //         const params = new URLSearchParams(search);
    //         params.delete("needsEmailActivation");
    //         window.history.replaceState(null, "", "?" + params + hash);
    //     }
    // }, [search, hash]);

    const handleSigninWithUsernamePassword = useCallback(
        (values: ISigninValues) => {
            login({ ...values })
                .then((authed) => {
                    if (!authed) return;

                    if (authed.email && !authed.isEmailVerified) {
                        verifyEmail({ email: authed.email })
                            .then(() => {
                                // noop
                            })
                            .catch(console.error);
                    } else if (authed.phone && !authed.isPhoneVerified) {
                        verifyPhone({ phone: authed.phone })
                            .then(() => {
                                // noop
                            })
                            .catch(console.error);
                    } else {
                        // router.visit(ROUTES.registration);
                    }
                })
                .catch(handleError);
        },
        [login, verifyEmail, verifyPhone],
    );

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

    if (userAuthedNotEmailVerified) {
        return (
            <div className="row mb-2">
                <div className="col">
                    <div className="row my-3">
                        <div className="col white">Please verify your email address.</div>
                    </div>
                    <div className="row">
                        <div className="col">
                            <Button disabled={disabled} variant="info" onClick={handleSendEmailVerification}>
                                Re-send Activation Email
                            </Button>
                        </div>
                    </div>
                    <div className="row mt-3">
                        <div className="col">
                            <Button disabled={disabled} variant="danger" onClick={logout}>
                                Cancel
                            </Button>
                        </div>
                    </div>
                </div>
            </div>
        );
    } else {
        return (
            <div className="col">
                <div className="row">
                    <div className="col">
                        <Formik
                            initialValues={INITIAL_VALUES}
                            onSubmit={handleSigninWithUsernamePassword}
                            validationSchema={VALIDATION_SCHEMA}
                        >
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
                                                        autoComplete="email"
                                                        isInvalid={Boolean(touched.email && errors.email)}
                                                        onBlur={handleBlur}
                                                        onChange={handleChange}
                                                    />
                                                </BootstrapForm.Group>
                                                <ErrorMessage name={"email"} className="bold white" />
                                            </div>
                                            <div className="col-lg-4 col-1">&nbsp;</div>
                                        </div>
                                        <div className="row mb-2">
                                            <div className="col-lg-4 col-1">&nbsp;</div>
                                            <div className="col-lg-4 col-10">
                                                <BootstrapForm.Group controlId="password">
                                                    <BootstrapForm.Control
                                                        disabled={disabled}
                                                        type="password"
                                                        name="password"
                                                        placeholder="Password"
                                                        autoComplete="password"
                                                        isInvalid={Boolean(touched.password && errors.password)}
                                                        onBlur={handleBlur}
                                                        onChange={handleChange}
                                                    />
                                                </BootstrapForm.Group>
                                                <ErrorMessage name={"password"} className="bold white" />
                                            </div>
                                            <div className="col-lg-4 col-1">&nbsp;</div>
                                        </div>
                                        <div className="row  mb-2">
                                            <div className="col text-center">
                                                <Button type="submit" size="lg" disabled={disabled}>
                                                    Sign In
                                                </Button>
                                            </div>
                                        </div>
                                        <div className="row">
                                            <div className="col text-center">
                                                {/* <Button
                                                    disabled={disabled}
                                                    size="sm"
                                                    variant="info"
                                                    onClick={() => router.visit(ROUTES.passwordreset)}
                                                >
                                                    Forgot Password?
                                                </Button> */}
                                                <InertiaLink href={ROUTES.passwordreset} as="button" className="btn btn-primary">Forgot Password?</InertiaLink>
                                            </div>
                                        </div>
                                    </Form>
                                );
                            }}
                        </Formik>
                    </div>
                </div>
                <hr
                    style={{
                        color: "white",
                        width: IS_MOBILE_PHONE ? "75%" : "50%",
                        textAlign: "center",
                        margin: "20px auto",
                    }}
                />

                <div className="row mb-2">
                    <div className="col">
                        <Button
                            disabled={disabled}
                            size="lg"
                            variant="info"
                            // onClick={() => router.visit(ROUTES.sign_up)}
                        >
                            Sign Up
                        </Button>
                    </div>
                </div>
            </div>
        );
    }
};
export default LoginForm;
