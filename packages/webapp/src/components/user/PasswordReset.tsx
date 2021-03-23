/** @format */

import { Button } from "@material-ui/core";
import { ArrowBack } from "@material-ui/icons";
import { useState } from "react";
import { useHistory } from "react-router-dom";
import { auth } from "../../firebase";
import { recaptcha } from "../../users/signinAnonymously";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const PasswordReset = () => {
    const history = useHistory();
    const [email, setEmail] = useState("");

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

        recaptcha()
            .then(() => {
                auth.sendPasswordResetEmail(email)
                    .then(() => {
                        notify({
                            level: "success",
                            title: "Reset email sent.",
                        });
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
                        placeholder="Email"
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
