/** @format */

import { Button } from "@material-ui/core";
import { ArrowBack } from "@material-ui/icons";
import React, { useState } from "react";
import { useHistory } from "react-router-dom";
import { auth, authConstructor } from "../../firebase";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const SignUp = () => {
    const history = useHistory();
    const [email, setEmail] = useState<string>("");
    const [password, setPassword] = useState<string>("");
    const [passwordConfirmation, setPasswordConfirmation] = useState<string>(
        "",
    );
    const [recaptchaVerifier, setRecaptchaVerifier] = useState<firebase.default.auth.RecaptchaVerifier | undefined>();

    const handleNavigateBack = () => {
        history.goBack();
    };

    React.useEffect(() => {
        // set recaptcha object after component has mounted
        // this is done so that the <div id="recaptcha" /> has been rendered
        setRecaptchaVerifier(
            new authConstructor.RecaptchaVerifier("recaptcha", {
                size: "invisible",
            }),
        );
    }, []);

    const handleUserSignedUp = async (result: firebase.default.auth.UserCredential) => {
        if (!result.user) {
            handleError(new Error("Could not get user from signup response."));
            return;
        }
        result.user
            .sendEmailVerification()
            .then(() => {
                notify({
                    level: "success",
                    title: "Verification Email Sent",
                    message:
                        "Please check your email and confirm your account.",
                });
                setTimeout(() => {
                    handleNavigateBack();
                }, 2000);
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
        if (!recaptchaVerifier) {
            console.error("error verifying captcha for reset email");
            return;
        }

        recaptchaVerifier.render().then(() => {
            recaptchaVerifier.verify().then(() => {
                auth.createUserWithEmailAndPassword(email, password)
                    .then(handleUserSignedUp)
                    .catch(handleError);
            }).catch(handleError);
        }).catch(handleError);
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
                    />
                    <input
                        type="password"
                        name="userPassword"
                        value={password}
                        placeholder="Password"
                        id="userPassword"
                        onChange={onChangeHandler}
                    />
                    <input
                        type="password"
                        name="userPasswordConfirmation"
                        value={passwordConfirmation}
                        placeholder="Confirm Password"
                        id="userPasswordConfirmation"
                        onChange={onChangeHandler}
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
