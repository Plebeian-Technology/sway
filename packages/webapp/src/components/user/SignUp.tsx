/** @format */

import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import {
    createUserWithEmailAndPassword,
    EmailAuthProvider,
    linkWithCredential,
    signInWithCredential,
    UserCredential,
} from "firebase/auth";
import { ErrorMessage, Form, Formik } from "formik";
import { omit } from "lodash";
import { useCallback, useState } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { FiArrowLeft } from "react-icons/fi";
import { useDispatch } from "react-redux";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import * as yup from "yup";
import { NON_SERIALIZEABLE_FIREBASE_FIELDS } from "../../constants/users";
import { auth } from "../../firebase";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { useUserInviteUuid } from "../../hooks/users/useUserInviteUuid";
import { setUser } from "../../redux/actions/userActions";
import { handleError, localGet, localSet, SWAY_STORAGE } from "../../utils";
import SwaySpinner from "../SwaySpinner";
import LoginBubbles from "./LoginBubbles";

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
    const navigate = useNavigate();
    const invitedByUid = useUserInviteUuid();
    const sendEmailVerification = useEmailVerification();
    const [isLoading, setLoading] = useState<boolean>(false);

    const handleNavigateBack = useCallback(() => {
        navigate(-1);
    }, [navigate]);

    const navigateHome = useCallback(() => {
        logDev("navigate - to sigin from signup");
        navigate(`${ROUTES.signin}`, { replace: true });
    }, [navigate]);

    const handleAuthError = useCallback((error: Error) => {
        handleError(error, "Error signing up. Do you already have an account?");
    }, []);

    const handleUserSignedUp = useCallback(
        async (result: UserCredential) => {
            logDev("handleUserSignedUp.result", result);
            const { user } = result;
            if (!user) {
                setLoading(false);
                handleError(new Error("Could not get user from signup response."));
                return;
            }
            await sendEmailVerification(user)
                .then((verified: boolean) => {
                    setLoading(false);
                    if (verified) {
                        localSet(SWAY_STORAGE.Local.User.EmailConfirmed, "true");
                        dispatch(
                            setUser(
                                omit(
                                    {
                                        user: {
                                            email: user.email,
                                            uid: user.uid,
                                            isEmailVerified: true,
                                            isRegistrationComplete: !!localGet(
                                                SWAY_STORAGE.Local.User.Registered,
                                            ),
                                            invitedBy: invitedByUid,
                                        } as sway.IUser,
                                        settings: DEFAULT_USER_SETTINGS,
                                        isAdmin: false,
                                    },
                                    NON_SERIALIZEABLE_FIREBASE_FIELDS,
                                ),
                            ),
                        );
                        setTimeout(navigateHome, 5000);
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                });
        },
        [dispatch, invitedByUid, navigateHome, sendEmailVerification],
    );

    const handleSubmit = useCallback(
        async (values: ISignupValues) => {
            logDev("handleSubmit.values", values);
            setLoading(true);
            const { email, password } = values;
            if (auth.currentUser && auth.currentUser.isAnonymous) {
                logDev("sway signup: linking anon user with sway");
                const credential = EmailAuthProvider.credential(email, password);

                await linkWithCredential(auth.currentUser, credential)
                    .catch((error: firebase.default.auth.AuthError) => {
                        setLoading(false);
                        if (error.credential && error.code === "auth/credential-already-in-use") {
                            return signInWithCredential(auth, error.credential);
                        } else {
                            throw error;
                        }
                    })
                    .then(handleUserSignedUp)
                    .catch((e) => {
                        setLoading(false);
                        handleAuthError(e);
                    });
            } else {
                logDev("sway signup: authing user with sway");
                await createUserWithEmailAndPassword(auth, email, password)
                    .then(handleUserSignedUp)
                    .catch((e) => {
                        setLoading(false);
                        handleAuthError(e);
                    });
            }
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
