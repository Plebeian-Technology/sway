/** @format */

import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { findNotCongressLocale, isEmptyObject, logDev } from "@sway/utils";
import { AuthError, signInWithEmailAndPassword, UserCredential } from "firebase/auth";
import { isEmpty } from "lodash";
import { useCallback, useState } from "react";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { auth } from "../firebase";
import { signInWithApple } from "../users/signinWithApple";
import { signInWithGoogle } from "../users/signInWithGoogle";
import { signInWithTwitter } from "../users/signInWithTwitter";
import {
    handleError,
    localSet,
    notify,
    removeTimestamps,
    swayFireClient,
    SWAY_STORAGE,
} from "../utils";
import { useEmailVerification } from "./useEmailVerification";
import { useLocale } from "./useLocales";
import { useSwayUser } from "./users/useSwayUser";

// eslint-disable-next-line
export enum EProvider {
    Apple = "Apple",
    Google = "Google",
    Twitter = "Twitter",
}

interface ISigninValues {
    email: string;
    password: string;
}

const errorMessage = (provider: EProvider) =>
    `Error logging in with ${provider}.\n\nDo you already have an account through a different method?`;

export const useSignIn = () => {
    const navigate = useNavigate();
    const sendEmailVerification = useEmailVerification();

    const [, dispatchSwayUser] = useSwayUser();
    const [, dispatchLocale] = useLocale();

    const [isLoading, setLoading] = useState<boolean>(false);

    const handleUserLoggedIn = useCallback(
        async (result: UserCredential | void): Promise<undefined | void> => {
            const user = result?.user;

            logDev("handleUserLoggedIn.user", user);

            if (!user || isEmptyObject(user)) {
                const error = new Error(
                    "No user returned from provider. Please try closing Sway and logging in again.",
                );
                handleError(error);
            }

            if (!user?.uid) {
                setLoading(false);
                const error = new Error(
                    "No user UID returned from provider. Please try closing Sway and logging in again.",
                );
                handleError(error);
            } else if (user.emailVerified === false) {
                setLoading(false);
                notify({
                    level: "info",
                    title: "Please verify your email address.",
                    message: user
                        ? "Click here to re-send the verification email."
                        : "Check your email for a message from noreply@sway.vote.",
                    duration: 20000,
                    onClick: () => {
                        if (!user) return;
                        sendEmailVerification(user).catch(handleError);
                    },
                });
                return navigate(`${ROUTES.signin}?needsEmailActivation=1`, { replace: true });
            } else {
                await swayFireClient()
                    .users(user.uid)
                    .getWithSettings()
                    .then((userWithSettings) => {
                        if (userWithSettings) {
                            localSet(SWAY_STORAGE.Local.User.SignedIn, "true");
                            if (user.emailVerified) {
                                localSet(SWAY_STORAGE.Local.User.EmailConfirmed, "true");
                            }
                            if (userWithSettings.user.isRegistrationComplete) {
                                localSet(SWAY_STORAGE.Local.User.Registered, "true");
                            }

                            return {
                                ...removeTimestamps(userWithSettings),
                                user: {
                                    ...removeTimestamps(userWithSettings.user),
                                    isEmailVerified: Boolean(user.emailVerified),
                                },
                            };
                        } else {
                            return {
                                user: {
                                    email: user.email,
                                    uid: user.uid,
                                    isEmailVerified: user.emailVerified,
                                    isRegistrationComplete: false,
                                } as sway.IUser,
                                settings: DEFAULT_USER_SETTINGS,
                                isAdmin: false,
                            };
                        }
                    })
                    .then((userWithSettings) => {
                        dispatchSwayUser(userWithSettings);
                        const userLocales = userWithSettings.user.locales;
                        if (!isEmpty(userLocales)) {
                            dispatchLocale(
                                findNotCongressLocale(userLocales) || userLocales.first(),
                            );
                        }
                        return userWithSettings;
                    })
                    .then((userWithSettings) => {
                        setTimeout(() => logDev("sleep"), 100);
                        const {
                            user: { isRegistrationComplete, isEmailVerified },
                        } = userWithSettings;
                        if (isRegistrationComplete && isEmailVerified) {
                            logDev(
                                "signin.handleUserLoggedIn - !user.isRegistrationComplete && user.isEmailVerified - GO TO REGISTRATION",
                            );
                            navigate(ROUTES.legislators, { replace: true });
                        } else {
                            navigate(ROUTES.registration, { replace: true });
                        }
                    })
                    .catch((e) => {
                        setLoading(false);
                        handleError(e);
                    });
            }
        },
        [navigate, dispatchSwayUser, dispatchLocale, sendEmailVerification],
    );

    const handleSigninWithUsernamePassword = useCallback(
        (values: ISigninValues) => {
            setLoading(true);
            signInWithEmailAndPassword(auth, values.email, values.password)
                .then(handleUserLoggedIn)
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                });
        },
        [handleUserLoggedIn],
    );

    const handleSigninWithSocialProvider = useCallback(
        (provider: EProvider) => {
            logDev("handleSigninWithSocialProvider with provider -", provider);
            const method = {
                [EProvider.Google]: signInWithGoogle,
                [EProvider.Apple]: signInWithApple,
                [EProvider.Twitter]: signInWithTwitter,
            }[provider];

            method()
                .then((credential: UserCredential | void) => {
                    if (credential) {
                        notify({
                            level: "success",
                            title: `Signed in with ${provider}.`,
                            duration: 2000,
                        });
                        return credential;
                    }
                })
                .then(handleUserLoggedIn)
                .catch((error: AuthError) => {
                    setLoading(false);
                    if (
                        error.code &&
                        [
                            "auth/popup-closed-by-user",
                            "auth/cancelled-popup-request",
                            "auth/user-cancelled",
                        ].includes(error.code)
                    ) {
                        console.warn(error);
                    } else {
                        handleError(error, errorMessage(provider));
                    }
                });
        },
        [handleUserLoggedIn],
    );

    return {
        handleUserLoggedIn,
        handleSigninWithUsernamePassword,
        handleSigninWithSocialProvider,
        isLoading,
        setLoading,
    };
};
