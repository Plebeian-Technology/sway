/** @format */

import { Typography } from "@material-ui/core";
import { ROUTES } from "@sway/constants";
import React, { useState } from "react";
import { Link } from "react-router-dom";
import appleButton from "../../assets/apple-button-white.png";
import googleButton from "../../assets/btn_google_signin_dark_normal_web.png";
import sway from "../../assets/sway-us-light.png";
import twitterButton from "../../assets/twitter-signin-button.png";
import { auth } from "../../firebase";
import { useSignIn } from "../../hooks/signin";
import { handleError } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const SignIn: React.FC = () => {
    const {
        handleUserLoggedIn,
        handleGoogleSignin,
        handleAppleSignin,
        handleTwitterSignin,
    } = useSignIn();
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");

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

    return (
        <LoginBubbles title={""}>
            <div className={"container"}>
                <form className="login-form">
                    <img src={sway} alt={"Sway"} style={{ marginBottom: 10, }} />
                    <input
                        type="email"
                        name="userEmail"
                        value={email}
                        placeholder="Email"
                        id="userEmail"
                        onChange={onChangeHandler}
                    />
                    <input
                        type="password"
                        name="userPassword"
                        value={password}
                        placeholder="Password"
                        id="userPassword"
                        onChange={onChangeHandler}
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
                                onClick={handleAppleSignin}
                                alt={"Sign in with Apple"}
                                src={appleButton}
                            />
                        </div>
                        <div>
                            <img
                                onClick={handleGoogleSignin}
                                alt={"Sign in with Google"}
                                src={googleButton}
                            />
                        </div>
                        <div>
                            <img
                                onClick={handleTwitterSignin}
                                alt={"Sign in with Twitter"}
                                src={twitterButton}
                            />
                        </div>
                    </div>
                </div>
            </div>
        </LoginBubbles>
    );
};
export default SignIn;
