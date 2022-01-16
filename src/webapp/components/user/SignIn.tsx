/** @format */

import { Button, TextField, Typography } from "@mui/material";
import { ROUTES } from "src/constants";
import { ErrorMessage, Field, Form, Formik } from "formik";
import { useEffect } from "react";
import { Link } from "react-router-dom";
import * as yup from "yup";
import { auth } from "../../firebase";
import { useSignIn } from "../../hooks/signin";
import { handleError, notify, SWAY_COLORS } from "../../utils";
import SocialButtons from "../SocialButtons";
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
                    title: `Activation email sent to ${auth?.currentUser?.email}`,
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
            <div className={"container text-center"}>
                <Formik
                    initialValues={INITIAL_VALUES}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                >
                    {({ touched, errors, setFieldTouched, setFieldValue }) => {
                        const _setFieldValue = (
                            e: React.ChangeEvent<HTMLInputElement>,
                        ) => {
                            const { name, value } = e.target;
                            setFieldValue(name, value);
                        };

                        return (
                            <Form>
                                <div className="row">
                                    <div className="col">
                                        <img
                                            src={"/sway-us-light.png"}
                                            alt={"Sway"}
                                        />
                                    </div>
                                </div>
                                <div className="row my-1">
                                    <div className="col">
                                        <Field
                                            fullWidth
                                            type="email"
                                            name="email"
                                            placeholder="Email"
                                            id="email"
                                            autoComplete="email"
                                            margin={"dense"}
                                            variant={"filled"}
                                            onChange={_setFieldValue}
                                            error={Boolean(
                                                touched.email && errors.email,
                                            )}
                                            onBlur={() =>
                                                setFieldTouched("email")
                                            }
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
                                    </div>
                                </div>
                                <div className="row my-1">
                                    <div className="col">
                                        <Field
                                            fullWidth
                                            type="password"
                                            name="password"
                                            placeholder="Password"
                                            id="password"
                                            autoComplete="new-password"
                                            margin={"dense"}
                                            variant={"filled"}
                                            onChange={_setFieldValue}
                                            error={Boolean(
                                                touched.password &&
                                                    errors.password,
                                            )}
                                            onBlur={() =>
                                                setFieldTouched("password")
                                            }
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
                                    </div>
                                </div>
                                <div className="row my-1">
                                    <div className="col">
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
                                    </div>
                                </div>
                            </Form>
                        );
                    }}
                </Formik>
                <div className="row my-1">
                    <div className="col">
                        {auth.currentUser &&
                            !auth.currentUser.isAnonymous &&
                            !auth.currentUser.emailVerified && (
                                <Typography
                                    onClick={handleResendActivationEmail}
                                >
                                    <Link to={"/"}>
                                        Resend Activation Email
                                    </Link>
                                </Typography>
                            )}
                        <Typography>
                            {"Don't have an account?"}
                            <Link to={ROUTES.signup}>
                                {" Sign Up Here"}
                            </Link>{" "}
                            <br />
                        </Typography>
                        <Typography>
                            <Link to={ROUTES.passwordreset}>
                                Forgot Password?
                            </Link>
                        </Typography>
                    </div>
                </div>
                <div className="row my-1">
                    <div className="col">
                        <SocialButtons
                            handleSigninWithSocialProvider={
                                handleSigninWithSocialProvider
                            }
                        />
                    </div>
                </div>
            </div>
        </LoginBubbles>
    );
};
export default SignIn;
