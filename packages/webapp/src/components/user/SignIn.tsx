/** @format */

import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import { signInWithEmailAndPassword } from "firebase/auth";
import { ErrorMessage, Form, Formik } from "formik";
import { omit } from "lodash";
import { useEffect } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { useDispatch } from "react-redux";
import { useLocation, useNavigate } from "react-router-dom";
import * as yup from "yup";
import { auth } from "../../firebase";
import { NON_SERIALIZEABLE_FIREBASE_FIELDS, useUserWithSettingsAdmin } from "../../hooks";
import { useSignIn } from "../../hooks/signin";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { setUser } from "../../redux/actions/userActions";
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
    const location = useLocation();
    const dispatch = useDispatch();
    const user = useUserWithSettingsAdmin();
    const { sendEmailVerification } = useEmailVerification();
    const { handleUserLoggedIn, handleSigninWithSocialProvider } = useSignIn();

    useEffect(() => {
        const needsActivationQS: string | null = new URLSearchParams(location.search).get(
            "needsEmailActivation",
        );
        if (needsActivationQS === "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
            });
            const params = new URLSearchParams(location.search);
            params.delete("needsEmailActivation");
            window.history.replaceState(null, "", "?" + params + location.hash);
        }
    }, []);

    const handleResendActivationEmail = () => {
        if (!auth.currentUser) return;

        sendEmailVerification(auth.currentUser).catch(handleError);
    };

    const handleSubmit = (values: ISigninValues) => {
        logDev({ values });
        signInWithEmailAndPassword(auth, values.email, values.password)
            .then(handleUserLoggedIn)
            .catch(handleError);
    };

    const userAuthedNotEmailVerified =
        auth.currentUser && !auth.currentUser.isAnonymous && !auth.currentUser.emailVerified;

    useEffect(() => {
        const interval = setInterval(async () => {
            if (auth.currentUser && userAuthedNotEmailVerified && !user?.user?.isEmailVerified) {
                logDev("SignIn.useEffect.interval - Reloading firebase user.");
                await auth.currentUser.reload().catch(handleError);
                logDev(
                    "SignIn.useEffect.interval - firebase user EMAIL VERIFIED. Sway user EMAIL NOT VERIFIED. Reloading firebase user.",
                    {
                        user: {
                            ...user.user,
                            isEmailVerified: auth.currentUser.emailVerified,
                        },
                    },
                );
                if (auth.currentUser.emailVerified) {
                    logDev(
                        "SignIn.useEffect.interval - dispatch updated userWithSettingsAdmin with EMAIL IS VERIFIED.",
                    );
                    dispatch(
                        setUser(
                            omit(
                                {
                                    user: {
                                        ...user.user,
                                        isEmailVerified: auth.currentUser.emailVerified,
                                    },
                                },
                                NON_SERIALIZEABLE_FIREBASE_FIELDS,
                            ),
                        ),
                    );
                    if (user.user.isRegistrationComplete) {
                        navigate(ROUTES.legislators);
                    } else {
                        navigate(ROUTES.registration);
                    }
                }
            }
        }, 2000);
        return () => clearInterval(interval);
    }, [userAuthedNotEmailVerified, user?.user?.isEmailVerified]);

    const render = () => {
        if (userAuthedNotEmailVerified) {
            return (
                <div className="row mb-2">
                    <div className="col">
                        <div className="row my-3">
                            <div className="col white">Please verify your email address.</div>
                        </div>
                        <div className="row">
                            <div className="col">
                                <Button variant="info" onClick={handleResendActivationEmail}>
                                    Re-send Activation Email
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
                    {process.env.REACT_APP_TAURI !== "1" && (
                        <div className="row mt-2">
                            <div className="col">
                                <SocialButtons
                                    handleSigninWithSocialProvider={handleSigninWithSocialProvider}
                                />
                            </div>
                        </div>
                    )}
                </div>
            );
        }
    };

    return (
        <LoginBubbles title={""}>
            <div>
                <div className="row pb-2">
                    <div className="col">
                        <img src={"/sway-us-light.png"} alt="Sway" />
                    </div>
                </div>
                <div className="row mt-2">
                    <div className="col">{render()}</div>
                </div>
            </div>
        </LoginBubbles>
    );
};
export default SignIn;
