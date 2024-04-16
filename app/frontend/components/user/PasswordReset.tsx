/** @format */

import { sendPasswordResetEmail } from "firebase/auth";
import { useCallback, useState } from "react";
import { Button, Form } from "react-bootstrap";
import { FiArrowLeft, FiSend } from "react-icons/fi";
import { useNavigate } from "react-router-dom";
import { auth } from "../../firebase";
import { handleError, notify } from "../../utils";
import LoginBubbles from "./LoginBubbles";

const PasswordReset = () => {
    const navigate = useNavigate();
    const [email, setEmail] = useState("");
    const [isLoading, setLoading] = useState<boolean>(false);

    const handleNavigateBack = useCallback(() => {
        navigate(-1);
    }, [navigate]);

    const onChangeHandler = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, value } = event.currentTarget;
        if (name === "email") {
            setEmail(value);
        }
    }, []);

    const sendResetEmail = useCallback(
        (event: React.MouseEvent<HTMLElement>) => {
            event.preventDefault();
            event.stopPropagation();

            setLoading(true);

            sendPasswordResetEmail(auth, email)
                .then(() => {
                    setLoading(false);
                    notify({
                        level: "success",
                        title: "Reset email sent.",
                    });
                })
                .catch((e) => {
                    handleError(e);
                    setLoading(false);
                });
        },
        [email],
    );

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
                        <div className="col-0 col-md-3 col-lg-4">&nbsp;</div>
                        <div className="col-12 col-md-6 col-lg-4">
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
                        <div className="col-0 col-md-3 col-lg-4">&nbsp;</div>
                    </div>
                    <div className="row">
                        <div className="col-0 col-md-3 col-lg-4">&nbsp;</div>
                        <div className="col-6 col-md-3 col-lg-2 text-start">
                            <Button
                                onClick={handleNavigateBack}
                                size="lg"
                                variant="light"
                                disabled={isLoading}
                            >
                                <FiArrowLeft />
                                &nbsp;Back
                            </Button>
                        </div>
                        <div className="col-6 col-md-3 col-lg-2 text-end">
                            <Button size="lg" onClick={sendResetEmail} disabled={isLoading}>
                                Submit&nbsp;
                                <FiSend />
                            </Button>
                        </div>
                    </div>
                    <div className="col-0 col-md-3 col-lg-4">&nbsp;</div>
                </Form>
            </div>
        </LoginBubbles>
    );
};
export default PasswordReset;
