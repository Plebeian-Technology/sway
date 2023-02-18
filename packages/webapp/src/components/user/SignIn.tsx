/** @format */

import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import { signInWithEmailAndPassword } from "firebase/auth";
import { ErrorMessage, Form, Formik } from "formik";
import { useCallback, useEffect, useMemo } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { useLocation, useNavigate } from "react-router-dom";
import * as yup from "yup";
import { auth } from "../../firebase";
import { useFirebaseUser, useLogout } from "../../hooks";
import { useSignIn } from "../../hooks/signin";
import { useEmailVerification } from "../../hooks/useEmailVerification";
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
    const { search, hash } = useLocation();
    const logout = useLogout();
    const [firebaseUser] = useFirebaseUser();
    const sendEmailVerification = useEmailVerification();
    const { handleUserLoggedIn, handleSigninWithSocialProvider } = useSignIn();

    useEffect(() => {
        logDev("SignIn.useEffect.needsActivationQS", search);
        const needsActivationQS: string | null = new URLSearchParams(search).get(
            "needsEmailActivation",
        );
        if (needsActivationQS === "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
            });
            const params = new URLSearchParams(search);
            params.delete("needsEmailActivation");
            window.history.replaceState(null, "", "?" + params + hash);
        }
    }, [search, hash]);

    const handleSendEmailVerification = useCallback(() => {
        sendEmailVerification(firebaseUser).catch(handleError);
    }, [sendEmailVerification, firebaseUser]);

    const handleSubmit = useCallback(
        (values: ISigninValues) => {
            signInWithEmailAndPassword(auth, values.email, values.password)
                .then(handleUserLoggedIn)
                .catch(handleError);
        },
        [handleUserLoggedIn],
    );

    const userAuthedNotEmailVerified = useMemo(
        () => firebaseUser?.uid && !firebaseUser?.isAnonymous && !firebaseUser?.emailVerified,
        [firebaseUser?.uid, firebaseUser?.isAnonymous, firebaseUser?.emailVerified],
    );

    const render = useMemo(() => {
        if (userAuthedNotEmailVerified) {
            return (
                <div className="row mb-2">
                    <div className="col">
                        <div className="row my-3">
                            <div className="col white">Please verify your email address.</div>
                        </div>
                        <div className="row">
                            <div className="col">
                                <Button variant="info" onClick={handleSendEmailVerification}>
                                    Re-send Activation Email
                                </Button>
                            </div>
                        </div>
                        <div className="row mt-3">
                            <div className="col">
                                <Button variant="danger" onClick={logout}>
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
                                onSubmit={handleSubmit}
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
                                                            type="email"
                                                            name="email"
                                                            placeholder="Email"
                                                            autoComplete="email"
                                                            isInvalid={Boolean(
                                                                touched.email && errors.email,
                                                            )}
                                                            onBlur={handleBlur}
                                                            onChange={handleChange}
                                                        />
                                                    </BootstrapForm.Group>
                                                    <ErrorMessage
                                                        name={"email"}
                                                        className="bold white"
                                                    />
                                                </div>
                                                <div className="col-lg-4 col-1">&nbsp;</div>
                                            </div>
                                            <div className="row mb-2">
                                                <div className="col-lg-4 col-1">&nbsp;</div>
                                                <div className="col-lg-4 col-10">
                                                    <BootstrapForm.Group controlId="password">
                                                        <BootstrapForm.Control
                                                            type="password"
                                                            name="password"
                                                            placeholder="Password"
                                                            autoComplete="password"
                                                            isInvalid={Boolean(
                                                                touched.password && errors.password,
                                                            )}
                                                            onBlur={handleBlur}
                                                            onChange={handleChange}
                                                        />
                                                    </BootstrapForm.Group>
                                                    <ErrorMessage
                                                        name={"password"}
                                                        className="bold white"
                                                    />
                                                </div>
                                                <div className="col-lg-4 col-1">&nbsp;</div>
                                            </div>
                                            <div className="row  mb-2">
                                                <div className="col text-center">
                                                    <Button type="submit" size="lg">
                                                        Sign In
                                                    </Button>
                                                </div>
                                            </div>
                                            <div className="row">
                                                <div className="col text-center">
                                                    <Button
                                                        size="sm"
                                                        variant="info"
                                                        onClick={() =>
                                                            navigate({
                                                                pathname: ROUTES.passwordreset,
                                                            })
                                                        }
                                                    >
                                                        Forgot Password?
                                                    </Button>
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
                            width: "75%",
                            textAlign: "center",
                            margin: "20px auto",
                        }}
                    />
                    {process.env.REACT_APP_TAURI !== "1" && (
                        <div className="row">
                            <div className="col">
                                <SocialButtons
                                    handleSigninWithSocialProvider={handleSigninWithSocialProvider}
                                />
                            </div>
                        </div>
                    )}
                    <hr
                        style={{
                            color: "white",
                            width: "75%",
                            textAlign: "center",
                            margin: "20px auto",
                        }}
                    />

                    <div className="row mb-2">
                        <div className="col">
                            <Button
                                size="lg"
                                variant="info"
                                onClick={() => navigate({ pathname: ROUTES.signup })}
                            >
                                Sign Up
                            </Button>
                        </div>
                    </div>
                </div>
            );
        }
    }, [
        navigate,
        handleSigninWithSocialProvider,
        handleSubmit,
        logout,
        userAuthedNotEmailVerified,
        handleSendEmailVerification,
    ]);

    return (
        <LoginBubbles title={""}>
            <div>
                <div className="row pb-2">
                    <div className="col">
                        <img src={"/sway-us-light.png"} alt="Sway" />
                    </div>
                </div>
                <div className="row mt-2">
                    <div className="col">{render}</div>
                </div>
            </div>
        </LoginBubbles>
    );
};
export default SignIn;
