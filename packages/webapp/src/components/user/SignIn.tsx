/** @format */

import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import { AuthError, sendEmailVerification, signInWithEmailAndPassword } from "firebase/auth";
import { ErrorMessage, Form, Formik } from "formik";
import { useEffect } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { useNavigate } from "react-router-dom";
import * as yup from "yup";
import { auth } from "../../firebase";
import { useSignIn } from "../../hooks/signin";
import { handleError, notify } from "../../utils";
import SocialButtons from "../SocialButtons";
import LoginBubbles from "./LoginBubbles";

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

const SignIn: React.FC = () => {
    const navigate = useNavigate();
    const { handleUserLoggedIn, handleSigninWithSocialProvider } = useSignIn();

    useEffect(() => {
        const search = window.location.search;
        const needsActivationQS: string | null = new URLSearchParams(search).get(
            "needsEmailActivation",
        );
        if (needsActivationQS === "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
            });
        }
    }, []);

    const handleResendActivationEmail = () => {
        if (!auth.currentUser) return;

        sendEmailVerification(auth.currentUser)
            .then(() => {
                notify({
                    level: "success",
                    title: `Activation email sent to ${auth?.currentUser?.email}`,
                });
            })
            .catch((error: AuthError) => {
                console.error(error);
                if (error.code === "auth/too-many-requests") {
                    notify({
                        level: "error",
                        title: "Error: Too many activation requests.",
                        message: "Please try again later.",
                    });
                } else {
                    notify({
                        level: "error",
                        title: "Error sending activation email.",
                        message: "Please try again later.",
                    });
                }
            });
    };

    const handleSubmit = (values: ISigninValues) => {
        logDev({ values });
        signInWithEmailAndPassword(auth, values.email, values.password)
            .then(handleUserLoggedIn)
            .catch(handleError);
    };

    return (
        <LoginBubbles title={""}>
            <div>
                <Formik
                    initialValues={INITIAL_VALUES}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                >
                    {({ errors, handleChange, touched, handleBlur }) => {
                        return (
                            <Form>
                                <div className="row pb-2">
                                    <div className="col">
                                        <img src={"/sway-us-light.png"} alt="Sway" />
                                    </div>
                                </div>
                                <div className="row my-2">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-10">
                                        <BootstrapForm.Group controlId="email">
                                            <BootstrapForm.Control
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
                                    <div className="col-1">&nbsp;</div>
                                </div>
                                <div className="row mb-2">
                                    <div className="col-1">&nbsp;</div>
                                    <div className="col-10">
                                        <BootstrapForm.Group controlId="password">
                                            <BootstrapForm.Control
                                                type="password"
                                                name="password"
                                                placeholder="Password"
                                                autoComplete="new-password"
                                                isInvalid={Boolean(
                                                    touched.password && errors.password,
                                                )}
                                                onBlur={handleBlur}
                                                onChange={handleChange}
                                            />
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"password"} className="bold white" />
                                    </div>
                                    <div className="col-1">&nbsp;</div>
                                </div>
                                <div className="row mb-4 pt-2">
                                    <div className="col">
                                        <Button type="submit" size="lg">
                                            Sign In
                                        </Button>
                                    </div>
                                </div>
                            </Form>
                        );
                    }}
                </Formik>
                <div className="row">
                    <div className="col">
                        {auth.currentUser &&
                            !auth.currentUser.isAnonymous &&
                            !auth.currentUser.emailVerified && (
                                <div className="row mb-2">
                                    <div className="col">
                                        <Button
                                            variant="info"
                                            onClick={handleResendActivationEmail}
                                        >
                                            Resend Activation Email
                                        </Button>
                                    </div>
                                </div>
                            )}
                        <div className="row mb-2">
                            <div className="col">
                                <Button
                                    variant="info"
                                    onClick={() => navigate({ pathname: ROUTES.passwordreset })}
                                >
                                    Forgot Password?
                                </Button>
                            </div>
                        </div>
                        <div className="row mb-2">
                            <div className="col">
                                <Button
                                    variant="info"
                                    onClick={() => navigate({ pathname: ROUTES.signup })}
                                >
                                    Sign Up
                                </Button>
                            </div>
                        </div>
                    </div>
                </div>
                <div className="row mt-2">
                    <div className="col">
                        <SocialButtons
                            handleSigninWithSocialProvider={handleSigninWithSocialProvider}
                        />
                    </div>
                </div>
            </div>
        </LoginBubbles>
    );
};
export default SignIn;
