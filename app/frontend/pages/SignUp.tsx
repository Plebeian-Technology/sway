/** @format */

import { ErrorMessage, Form, Formik } from "formik";
import { useCallback, useState } from "react";
import { Form as BootstrapForm, Button } from "react-bootstrap";
import { FiArrowLeft } from "react-icons/fi";
import { useDispatch } from "react-redux";
import { sway } from "sway";
import * as yup from "yup";
import LoginBubbles from "../components/LoginBubbles";
import SwaySpinner from "../components/SwaySpinner";
import { handleError, logDev } from "../sway_utils";

interface ISignupValues {
    email: string;
    password: string;
    passwordConfirmation: string;
}

const VALIDATION_SCHEMA = yup.object().shape({
    email: yup.string().email("Invalid email address.").required("Email is required."),
    password: yup.string().required("Password is required."),
    passwordConfirmation: yup
        .string()
        .required("Password confirmation is required.")
        .oneOf([yup.ref("password")], "Password and password confirmation must match."),
});

const INITIAL_VALUES: ISignupValues = {
    email: "",
    password: "",
    passwordConfirmation: "",
};

const SignUp = () => {
    const dispatch = useDispatch();
    const [isLoading, setLoading] = useState<boolean>(false);

    const handleNavigateBack = useCallback(() => {
        // navigate(-1);
    }, []);

    const navigateHome = useCallback(() => {
        logDev("navigate - to sigin from sign_up");
        // navigate(`${ROUTES.signin}`, { replace: true });
    }, []);

    const handleAuthError = useCallback((error: Error) => {
        handleError(error, "Error signing up. Do you already have an account?");
    }, []);

    const handleUserSignedUp = useCallback(
        async (user: sway.IUser) => {
            logDev("handleUserSignedUp.user", user);
            if (!user) {
                setLoading(false);
                handleError(new Error("Could not get user from sign_up response."));
                return;
            }
            // await sendEmailVerification(user)
            //     .then((verified: boolean) => {
            //         setLoading(false);
            //         if (verified) {
            //             localSet(SWAY_STORAGE.Local.User.EmailConfirmed, "true");
            //             dispatch(
            //                 setUser(
            //                     omit(
            //                         {
            //                             user: {
            //                                 email: user.email,
            //                                 id: user.id,
            //                                 isEmailVerified: true,
            //                                 isRegistrationComplete: !!localGet(
            //                                     SWAY_STORAGE.Local.User.Registered,
            //                                 ),
            //                             } as sway.IUser,
            //                             settings: DEFAULT_USER_SETTINGS,
            //                             isAdmin: false,
            //                         },
            //                         NON_SERIALIZEABLE_FIREBASE_FIELDS,
            //                     ),
            //                 ),
            //             );
            //             setTimeout(navigateHome, 5000);
            //         }
            //     })
            //     .catch((e) => {
            //         setLoading(false);
            //         handleError(e);
            //     });
        },
        [dispatch, navigateHome],
    );

    const handleSubmit = useCallback(
        async (values: ISignupValues) => {
            // logDev("handleSubmit.values", values);
            // setLoading(true);
            // const { email, password } = values;
            // if (auth.currentUser && auth.currentUser.isAnonymous) {
            //     logDev("sway sign_up: linking anon user with sway");
            //     const credential = EmailAuthProvider.credential(email, password);

            //     await linkWithCredential(auth.currentUser, credential)
            //         .catch((error: firebase.default.auth.AuthError) => {
            //             setLoading(false);
            //             if (error.credential && error.code === "auth/credential-already-in-use") {
            //                 return signInWithCredential(auth, error.credential);
            //             } else {
            //                 throw error;
            //             }
            //         })
            //         .then(handleUserSignedUp)
            //         .catch((e) => {
            //             setLoading(false);
            //             handleAuthError(e);
            //         });
            // } else {
            //     logDev("sway sign_up: authing user with sway");
            //     await createUserWithEmailAndPassword(auth, email, password)
            //         .then(handleUserSignedUp)
            //         .catch((e) => {
            //             setLoading(false);
            //             handleAuthError(e);
            //         });
            // }
        },
        [handleAuthError, handleUserSignedUp],
    );

    return (
        <LoginBubbles title={""}>
            <div className="container" style={{ maxWidth: 350 }}>
                <Formik
                    initialValues={INITIAL_VALUES}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                >
                    {({ touched, errors, handleChange }) => {
                        return (
                            <Form>
                                <div className="row my-3">
                                    <div className="col">
                                        <img
                                            src={"/sway-us-light.png"}
                                            alt={"Sway"}
                                            className="my-3"
                                        />
                                    </div>
                                </div>
                                <div className="row my-3">
                                    <div className="col">
                                        <BootstrapForm.Group controlId="email">
                                            <BootstrapForm.Control
                                                type="email"
                                                name="email"
                                                placeholder="Email"
                                                autoComplete="email"
                                                onChange={handleChange}
                                                disabled={isLoading}
                                                isInvalid={Boolean(touched.email && errors.email)}
                                            />
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"email"} />
                                    </div>
                                </div>

                                <div className="row my-3">
                                    <div className="col">
                                        <BootstrapForm.Group controlId="password">
                                            <BootstrapForm.Control
                                                type="password"
                                                name="password"
                                                placeholder="Password"
                                                autoComplete="new-password"
                                                onChange={handleChange}
                                                disabled={isLoading}
                                                isInvalid={Boolean(
                                                    touched.password && errors.password,
                                                )}
                                            />
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"password"} />
                                    </div>
                                </div>

                                <div className="row my-3">
                                    <div className="col">
                                        <BootstrapForm.Group controlId="passwordConfirmation">
                                            <BootstrapForm.Control
                                                type="password"
                                                name="passwordConfirmation"
                                                placeholder="Confirm Password"
                                                autoComplete="new-password"
                                                onChange={handleChange}
                                                disabled={isLoading}
                                                isInvalid={Boolean(
                                                    touched.passwordConfirmation &&
                                                        errors.passwordConfirmation,
                                                )}
                                            />
                                        </BootstrapForm.Group>
                                        <ErrorMessage name={"passwordConfirmation"} />
                                    </div>
                                </div>

                                <div className="row my-3">
                                    <div className="col text-start">
                                        <Button
                                            onClick={handleNavigateBack}
                                            size="lg"
                                            disabled={isLoading}
                                            variant="light"
                                        >
                                            <FiArrowLeft />
                                            &nbsp;Back
                                        </Button>
                                    </div>
                                    <div className="col text-end">
                                        <Button type="submit" size="lg" disabled={isLoading}>
                                            Sign Up
                                        </Button>
                                    </div>
                                </div>
                            </Form>
                        );
                    }}
                </Formik>
                <SwaySpinner isHidden={!isLoading} className="p-4" />
            </div>
        </LoginBubbles>
    );
};
export default SignUp;
