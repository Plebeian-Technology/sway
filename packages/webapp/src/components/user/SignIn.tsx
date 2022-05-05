/** @format */

import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import { AuthError, sendEmailVerification, signInWithEmailAndPassword } from "firebase/auth";
import { ErrorMessage, Form, Formik } from "formik";
import { useEffect } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { Link } from "react-router-dom";
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
            <div className={"container text-center"}>
                <Formik
                    initialValues={INITIAL_VALUES}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                >
                    {({ errors, handleChange, touched, handleBlur }) => {
                        return (
                            <Form>
                                <div className="row">
                                    <div className="col">
                                        <img src={"/sway-us-light.png"} alt="Sway" />
                                    </div>
                                </div>
                                <div className="row my-1">
                                    <div className="col">
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
                                        <ErrorMessage name={"email"} />
                                    </div>
                                </div>
                                <div className="row my-1">
                                    <div className="col">
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
                                        <ErrorMessage name={"password"} />
                                    </div>
                                </div>
                                <div className="row my-1">
                                    <div className="col">
                                        <Button type="submit" size="lg" className="mt-2 py-2 px-4">
                                            Sign In
                                        </Button>
                                    </div>
                                </div>
                            </Form>
                        );
                    }}
                </Formik>
                <div className="row my-1">
                    <div className="col">
                        {auth.currentUser &&
                            !auth.currentUser.isAnonymous &&
                            !auth.currentUser.emailVerified && (
                                <span onClick={handleResendActivationEmail}>
                                    <Link to={"/"}>Resend Activation Email</Link>
                                </span>
                            )}
                        <span>
                            Don't have an account?
                            <Link to={ROUTES.signup}>{" Sign Up Here"}</Link> <br />
                        </span>
                        <span>
                            <Link to={ROUTES.passwordreset}>Forgot Password?</Link>
                        </span>
                    </div>
                </div>
                <div className="row my-1">
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
