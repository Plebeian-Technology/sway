/** @format */

import { Button, TextField, Typography } from "@material-ui/core";
import { ROUTES } from "@sway/constants";
import { ErrorMessage, Field, Form, Formik } from "formik";
import { useEffect } from "react";
import { Link } from "react-router-dom";
import * as yup from "yup";
import { auth } from "../../firebase";
import { EProvider, useSignIn } from "../../hooks/signin";
import { handleError, notify, SWAY_COLORS } from "../../utils";
import LoginBubbles from "./LoginBubbles";

interface ISigninValues {
    email: string;
    password: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    email: yup
        .string()
        .email("Invalid email address.")
        .required("Email is required."),
    password: yup.string().required("Password is required."),
});

const INITIAL_VALUES: ISigninValues = {
    email: "",
    password: "",
};

const INPUT_PROPS = {
    style: {
        color: SWAY_COLORS.white,
        borderRadius: 5,
    },
};

const SignIn: React.FC = () => {
    const { handleUserLoggedIn, handleSigninWithSocialProvider } = useSignIn();

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

    const handleSubmit = (values: ISigninValues) => {
        auth.signInWithEmailAndPassword(values.email, values.password)
            .then(handleUserLoggedIn)
            .catch(handleError);
    };

    return (
        <LoginBubbles title={""}>
            <div className={"container"} style={{ maxWidth: 350 }}>
                <Formik
                    initialValues={INITIAL_VALUES}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                    style={{ zIndex: 10000 }}
                >
                    {({ touched, errors, setFieldTouched, setFieldValue }) => {
                        const _setFieldValue = (
                            e: React.ChangeEvent<HTMLInputElement>,
                        ) => {
                            const { name, value } = e.target;
                            setFieldValue(name, value);
                        };

                        return (
                            <Form className="signup-form">
                                <img
                                    src={"/sway-us-light.png"}
                                    alt={"Sway"}
                                    style={{ marginBottom: 10 }}
                                />
                                <Field
                                    fullWidth
                                    type="email"
                                    name="email"
                                    placeholder="Email"
                                    id="email"
                                    autoComplete="email"
                                    margin={"normal"}
                                    variant={"filled"}
                                    onChange={_setFieldValue}
                                    error={Boolean(
                                        touched.email && errors.email,
                                    )}
                                    onBlur={() => setFieldTouched("email")}
                                    component={TextField}
                                    inputProps={{
                                        ...INPUT_PROPS,
                                        name: "email",
                                    }}
                                    InputProps={{
                                        style: {
                                            ...INPUT_PROPS.style,
                                            backgroundColor:
                                                "rgba(0, 0, 0, 0.5)",
                                        },
                                    }}
                                />
                                <ErrorMessage
                                    name={"email"}
                                    component={Typography}
                                />
                                <Field
                                    fullWidth
                                    type="password"
                                    name="password"
                                    placeholder="Password"
                                    id="password"
                                    autoComplete="new-password"
                                    margin={"normal"}
                                    variant={"filled"}
                                    onChange={_setFieldValue}
                                    error={Boolean(
                                        touched.password && errors.password,
                                    )}
                                    onBlur={() => setFieldTouched("password")}
                                    component={TextField}
                                    inputProps={{
                                        ...INPUT_PROPS,
                                        name: "password",
                                    }}
                                    InputProps={{
                                        style: {
                                            ...INPUT_PROPS.style,
                                            backgroundColor:
                                                "rgba(0, 0, 0, 0.5)",
                                        },
                                    }}
                                />
                                <ErrorMessage
                                    name={"password"}
                                    component={Typography}
                                />
                                <Button
                                    type="submit"
                                    variant={"contained"}
                                    color={"primary"}
                                    size={"large"}
                                    style={{
                                        marginTop: 10,
                                        padding: "10px 30px",
                                    }}
                                >
                                    Sign In
                                </Button>
                            </Form>
                        );
                    }}
                </Formik>
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
