/** @format */

import { Typography } from "@material-ui/core";
import { ROUTES } from "@sway/constants";
import React, { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { auth } from "../../firebase";
import { EProvider, useSignIn } from "../../hooks/signin";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const SignIn: React.FC = () => {
    const { handleUserLoggedIn, handleSigninWithSocialProvider } = useSignIn();
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");

    useEffect(() => {
        const search = window.location.search;
        const needsActivationQS: string | null = new URLSearchParams(
            search,
        ).get("needsEmailActivation");
        if (needsActivationQS === "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
                message: "",
            });
        }
    }, []);

    const handleUsernamePasswordSignin = (
        event: React.MouseEvent<HTMLElement>,
    ) => {
        event.preventDefault();
        auth.signInWithEmailAndPassword(email, password)
            .then(handleUserLoggedIn)
            .catch(handleError);
    };

    const onChangeHandler = (event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, value } = event.currentTarget;
        name === "userEmail" ? setEmail(value) : setPassword(value);
    };

    const handleResendActivationEmail = () => {
        if (!auth.currentUser) return;

        auth.currentUser
            .sendEmailVerification()
            .then(() => {
                notify({
                    level: "success",
                    title: "Activation email sent!",
                    message: `Email sent to ${auth?.currentUser?.email}`,
                });
            })
            .catch((error) => {
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

    return (
        <LoginBubbles title={""}>
            <div className={"container"}>
                <form className="login-form">
                    <img
                        src={"/sway-us-light.png"}
                        alt={"Sway"}
                        style={{ marginBottom: 10 }}
                    />
                    <input
                        type="email"
                        name="userEmail"
                        value={email}
                        placeholder="Email"
                        id="userEmail"
                        onChange={onChangeHandler}
                        autoComplete="email"
                    />
                    <input
                        type="password"
                        name="userPassword"
                        value={password}
                        placeholder="Password"
                        id="userPassword"
                        onChange={onChangeHandler}
                        autoComplete="current-password"
                    />
                    <button
                        type="submit"
                        className="login-button"
                        onClick={handleUsernamePasswordSignin}
                    >
                        Sign In
                    </button>
                </form>
                <div id="subcontainer">
                    {auth.currentUser &&
                        !auth.currentUser.isAnonymous &&
                        !auth.currentUser.emailVerified && (
                            <Typography onClick={handleResendActivationEmail}>
                                <Link to={"/"}>Resend Activation Email</Link>
                            </Typography>
                        )}
                    <Typography>
                        {"Don't have an account?"}
                        <Link to={ROUTES.signup}>{" Sign Up Here"}</Link> <br />
                    </Typography>
                    <Typography>
                        <Link to={ROUTES.passwordreset}>Forgot Password?</Link>
                    </Typography>
                    <div className={"buttons-container"}>
                        <div>
                            <img
                                onClick={() =>
                                    handleSigninWithSocialProvider(
                                        EProvider.Apple,
                                    )
                                }
                                alt={"Sign in with Apple"}
                                src={"/apple-button-white.png"}
                            />
                        </div>
                        <div>
                            <img
                                onClick={() =>
                                    handleSigninWithSocialProvider(
                                        EProvider.Google,
                                    )
                                }
                                alt={"Sign in with Google"}
                                src={"/btn_google_signin_dark_normal_web.png"}
                            />
                        </div>
                        <div>
                            <img
                                onClick={() =>
                                    handleSigninWithSocialProvider(
                                        EProvider.Twitter,
                                    )
                                }
                                alt={"Sign in with Twitter"}
                                src={"/twitter-signin-button.png"}
                            />
                        </div>
                    </div>
                </div>
            </div>
        </LoginBubbles>
    );
};
export default SignIn;
