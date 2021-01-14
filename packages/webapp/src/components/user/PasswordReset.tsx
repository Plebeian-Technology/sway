/** @format */

import { Button } from "@material-ui/core";
import { ArrowBack } from "@material-ui/icons";
import { useEffect, useState } from "react";
import { useHistory } from "react-router-dom";
import { auth, authConstructor } from "../../firebase";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const PasswordReset = () => {
    const history = useHistory();
    const [email, setEmail] = useState("");
    const [recaptchaVerifier, setRecaptchaVerifier] = useState<
        firebase.default.auth.RecaptchaVerifier | undefined
    >();

    useEffect(() => {
        // set recaptcha object after component has mounted
        // this is done so that the <div id="recaptcha" /> has been rendered
        setRecaptchaVerifier(
            new authConstructor.RecaptchaVerifier("recaptcha", {
                size: "invisible",
            }),
        );
    }, []);

    const handleNavigateBack = () => {
        history.goBack();
    };

    const onChangeHandler = (event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, value } = event.currentTarget;
        if (name === "userEmail") {
            setEmail(value);
        }
    };
    const sendResetEmail = (event: React.MouseEvent<HTMLElement>) => {
        event.preventDefault();
        event.stopPropagation();

        if (!recaptchaVerifier) {
            console.error("error verifying captcha for reset email");
            return;
        }

        recaptchaVerifier
            .render()
            .then(() => {
                recaptchaVerifier
                    .verify()
                    .then(() => {
                        auth.sendPasswordResetEmail(email)
                            .then(() => {
                                notify({
                                    level: "success",
                                    title: "Reset Email Sent",
                                    message:
                                        "Please check your email for a password reset email.",
                                });
                            })
                            .catch(handleError);
                    })
                    .catch(handleError);
            })
            .catch(handleError);
    };
    return (
        <LoginBubbles title={"Password Reset"}>
            <div className={"container"}>
                <form className="login-form">
                    <input
                        type="email"
                        name="userEmail"
                        value={email}
                        placeholder="email"
                        id="userEmail"
                        onChange={onChangeHandler}
                    />
                    <button
                        type="button"
                        className="login-button"
                        onClick={sendResetEmail}
                    >
                        Send Reset Link
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
export default PasswordReset;
