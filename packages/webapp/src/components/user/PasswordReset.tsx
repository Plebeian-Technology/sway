/** @format */

import { ArrowBack } from "@mui/icons-material";
import { Button } from "@mui/material";
import { sendPasswordResetEmail } from "firebase/auth";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { auth } from "../../firebase";
import { recaptcha } from "../../users/signinAnonymously";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const PasswordReset = () => {
    const navigate = useNavigate();
    const [email, setEmail] = useState("");

    const handleNavigateBack = () => {
        navigate(-1);
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
                sendPasswordResetEmail(auth, email)
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
                    <button type="button" className="login-button" onClick={sendResetEmail}>
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
