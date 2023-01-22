/** @format */

import { sendPasswordResetEmail } from "firebase/auth";
import { useState } from "react";
import { Button, Form } from "react-bootstrap";
import { FiArrowLeft, FiSend } from "react-icons/fi";
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
        if (name === "email") {
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
            <div className="container">
                <Form className="col">
                    <div className="row">
                        <div className="col">
                            <img src={"/sway-us-light.png"} alt="Sway" />
                        </div>
                    </div>
                    <div className="row my-4">
                        <div className="col">
                            <Form.Group controlId="email">
                                <Form.Control
                                    type="email"
                                    name="email"
                                    value={email}
                                    placeholder="Email"
                                    onChange={onChangeHandler}
                                />
                            </Form.Group>
                        </div>
                    </div>
                    <div className="row">
                        <div className="col text-start">
                            <Button onClick={handleNavigateBack} size="lg" variant="light">
                                <FiArrowLeft />
                                &nbsp;Back
                            </Button>
                        </div>
                        <div className="col text-end">
                            <Button size="lg" onClick={sendResetEmail}>
                                Submit&nbsp;
                                <FiSend />
                            </Button>
                        </div>
                    </div>
                </Form>
            </div>
        </LoginBubbles>
    );
};
export default PasswordReset;
