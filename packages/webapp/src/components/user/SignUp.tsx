/** @format */

import { Button, TextField, Typography } from "@material-ui/core";
import { ArrowBack } from "@material-ui/icons";
import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import { ErrorMessage, Field, Form, Formik } from "formik";
import { useDispatch } from "react-redux";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import * as yup from "yup";
import { auth } from "../../firebase";
import { setUser } from "../../redux/actions/userActions";
import { recaptcha } from "../../users/signinAnonymously";
import { handleError, notify, SWAY_COLORS } from "../../utils";
import LoginBubbles from "./LoginBubbles";

interface ISignupValues {
    email: string;
    password: string;
    passwordConfirmation: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    email: yup
        .string()
        .email("Invalid email address.")
        .required("Email is required."),
    password: yup.string().required("Password is required."),
    passwordConfirmation: yup
        .string()
        .required("Password confirmation is required.")
        .oneOf(
            [yup.ref("password")],
            "Password and password confirmation must match.",
        ),
});

const INITIAL_VALUES: ISignupValues = {
    email: "",
    password: "",
    passwordConfirmation: "",
};

const INPUT_PROPS = {
    style: {
        color: SWAY_COLORS.white,
        borderRadius: 5,
    },
};

const SignUp = () => {
    const dispatch = useDispatch();
    const history = useHistory();

    const handleNavigateBack = () => {
        history.goBack();
    };

    const handleNavigateToRegistration = () => {
        logDev("navigate - to registration from signup");
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
                    message:
                        "Activation email sent. Please check your email and confirm your account.",
                });
                setTimeout(() => {
                    handleNavigateToRegistration();
                }, 3000);
            })
            .catch(handleError);
    };

    const handleSubmit = (values: ISignupValues) => {
        recaptcha()
            .then(() => {
                auth.createUserWithEmailAndPassword(
                    values.email,
                    values.password,
                )
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
                                    style={{ marginBottom: 10, marginTop: -20 }}
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
                                            ...INPUT_PROPS,
                                            backgroundColor:
                                                "rgba(0, 0, 0, 0.5)",
                                            borderRadius: 5,
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
                                            ...INPUT_PROPS,
                                            backgroundColor:
                                                "rgba(0, 0, 0, 0.5)",
                                            borderRadius: 5,
                                        },
                                    }}
                                />
                                <ErrorMessage
                                    name={"password"}
                                    component={Typography}
                                />
                                <Field
                                    fullWidth
                                    type="password"
                                    name="passwordConfirmation"
                                    placeholder="Confirm Password"
                                    id="passwordConfirmation"
                                    autoComplete="new-password"
                                    margin={"normal"}
                                    variant={"filled"}
                                    onChange={_setFieldValue}
                                    error={Boolean(
                                        touched.passwordConfirmation &&
                                            errors.passwordConfirmation,
                                    )}
                                    onBlur={() =>
                                        setFieldTouched("passwordConfirmation")
                                    }
                                    component={TextField}
                                    inputProps={{
                                        ...INPUT_PROPS,
                                        name: "passwordConfirmation",
                                    }}
                                    InputProps={{
                                        style: {
                                            ...INPUT_PROPS,
                                            backgroundColor:
                                                "rgba(0, 0, 0, 0.5)",
                                            borderRadius: 5,
                                        },
                                    }}
                                />
                                <ErrorMessage
                                    name={"passwordConfirmation"}
                                    component={Typography}
                                />
                                <Button
                                    type="submit"
                                    variant={"contained"}
                                    color={"primary"}
                                    size={"large"}
                                    style={{
                                        marginTop: 10,
                                        padding: "20px 50px",
                                    }}
                                >
                                    Sign Up
                                </Button>
                            </Form>
                        );
                    }}
                </Formik>
                <Button
                    style={{ zIndex: 10000, marginTop: 40 }}
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
