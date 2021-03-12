/** @format */

import { Button } from "@material-ui/core";
import { ArrowBack } from "@material-ui/icons";
import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { IS_DEVELOPMENT } from "@sway/utils";
import React, { useState } from "react";
import { useDispatch } from "react-redux";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { auth } from "../../firebase";
import { setUser } from "../../redux/actions/userActions";
import { recaptcha } from "../../users/signinAnonymously";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const SignUp = () => {
    const dispatch = useDispatch();
    const history = useHistory();
    const [email, setEmail] = useState<string>("");
    const [password, setPassword] = useState<string>("");
    const [passwordConfirmation, setPasswordConfirmation] = useState<string>(
        "",
    );

    const handleNavigateBack = () => {
        history.goBack();
    };

    const handleNavigateToRegistration = () => {
        IS_DEVELOPMENT &&
            console.log("(dev) navigate - to registration from signup");
        history.push(ROUTES.registrationIntroduction);
    };

    const handleUserSignedUp = async (
        result: firebase.default.auth.UserCredential,
    ) => {
        const { user } = result;
        if (!user) {
            handleError(new Error("Could not get user from signup response."));
            return;
        }
        user.sendEmailVerification()
            .then(() => {
                dispatch(
                    setUser({
                        user: {
                            email: user.email,
                            uid: user.uid,
                            isEmailVerified: false,
                            isRegistrationComplete: false,
                        } as sway.IUser,
                        settings: DEFAULT_USER_SETTINGS,
                    }),
                );
                notify({
                    level: "success",
                    title: "Verification Email Sent",
                    message:
                        "Please check your email and confirm your account.",
                });
                setTimeout(() => {
                    handleNavigateToRegistration();
                }, 3000);
            })
            .catch(handleError);
    };

    const createUserWithEmailAndPasswordHandler = (
        e: React.MouseEvent<HTMLElement>,
    ) => {
        e.preventDefault();
        e.stopPropagation();

        if (password !== passwordConfirmation) {
            notify({
                level: "error",
                title: "Password Mismatch",
                message: "Password and confirmation do not match.",
            });
            return;
        }
        recaptcha()
            .then(() => {
                auth.createUserWithEmailAndPassword(email, password)
                    .then(handleUserSignedUp)
                    .catch((error) => {
                        handleError(
                            error,
                            "Error signing up. Do you already have an account?",
                        );
                    });
            })
            .catch(handleError);
    };

    const onChangeHandler = (event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, value } = event.currentTarget;
        if (name === "userEmail") {
            setEmail(value);
        } else if (name === "userPassword") {
            setPassword(value);
        } else if (name === "userPasswordConfirmation") {
            setPasswordConfirmation(value);
        }
    };

    return (
        <LoginBubbles title={"Sign Up"}>
            <div className={"container"}>
                <form className="login-form">
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
                        autoComplete="new-password"
                    />
                    <input
                        type="password"
                        name="userPasswordConfirmation"
                        value={passwordConfirmation}
                        placeholder="Confirm Password"
                        id="userPasswordConfirmation"
                        onChange={onChangeHandler}
                        autoComplete="new-password"
                    />
                    <button
                        type="submit"
                        id="signup-submit"
                        className="login-button"
                        onClick={createUserWithEmailAndPasswordHandler}
                    >
                        Sign Up
                    </button>
                </form>
                <Button
                    style={{ zIndex: 3 }}
                    onClick={handleNavigateBack}
                    startIcon={<ArrowBack />}
                >
                    Back
                </Button>
            </div>
        </LoginBubbles>
    );
};
export default SignUp;
