/** @format */

import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import { ErrorMessage, Form, Formik } from "formik";
import { useCallback, useEffect, useMemo } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { useLocation, useNavigate } from "react-router-dom";
import * as yup from "yup";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { useFirebaseUser } from "../../hooks/users/useFirebaseUser";
import { useLogout } from "../../hooks/users/useUser";
import { useSignIn } from "../../hooks/useSignIn";
import { handleError, IS_MOBILE_PHONE, notify } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
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
    const [firebaseUser, isLoadingFirebaseUser] = useFirebaseUser();
    const {
        handleSigninWithUsernamePassword,
        handleSigninWithSocialProvider,
        isLoading,
        setLoading,
    } = useSignIn();
    const disabled = useMemo(
        () => isLoadingFirebaseUser || isLoading,
        [isLoadingFirebaseUser, isLoading],
    );
    logDev("Signin.isLoadingFirebaseUser", { isLoadingFirebaseUser, isLoading, disabled });

    const sendEmailVerification = useEmailVerification();

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
                                <Button
                                    disabled={disabled}
                                    variant="info"
                                    onClick={handleSendEmailVerification}
                                >
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
                                                            disabled={disabled}
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
                                                    <Button
                                                        type="submit"
                                                        size="lg"
                                                        disabled={disabled}
                                                    >
                                                        Sign In
                                                    </Button>
                                                </div>
                                            </div>
                                            <div className="row">
                                                <div className="col text-center">
                                                    <Button
                                                        disabled={disabled}
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
                            width: IS_MOBILE_PHONE ? "75%" : "50%",
                            textAlign: "center",
                            margin: "20px auto",
                        }}
                    />
                    {process.env.REACT_APP_TAURI !== "1" && (
                        <div className="row">
                            <div className="col">
                                <SocialButtons
                                    handleSigninWithSocialProvider={handleSigninWithSocialProvider}
                                    disabled={disabled}
                                    setLoading={setLoading}
                                />
                            </div>
                        </div>
                    )}
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
        handleSigninWithUsernamePassword,
        logout,
        userAuthedNotEmailVerified,
        handleSendEmailVerification,
        disabled,
        setLoading,
    ]);

    return (
        <LoginBubbles title={""}>
            {isLoading && <FullScreenLoading />}
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
