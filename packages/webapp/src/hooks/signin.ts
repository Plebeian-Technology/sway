/** @format */

import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { findNotCongressLocale, isEmptyObject, logDev } from "@sway/utils";
import { AuthError, UserCredential } from "firebase/auth";
import { isEmpty } from "lodash";
import { useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { signInWithApple } from "../users/signinWithApple";
import { signInWithGoogle } from "../users/signInWithGoogle";
import { signInWithTwitter } from "../users/signInWithTwitter";
import { handleError, notify, removeTimestamps, swayFireClient } from "../utils";
import { useLocale } from "./locales";
import { useEmailVerification } from "./useEmailVerification";
import { useSwayUser } from "./users";

// eslint-disable-next-line
export enum EProvider {
    Apple = "Apple",
    Google = "Google",
    Twitter = "Twitter",
}

const errorMessage = (provider: EProvider) =>
    `Error logging in with ${provider}.\n\nDo you already have an account through a different method?`;

export const useSignIn = () => {
    const navigate = useNavigate();
    const sendEmailVerification = useEmailVerification();

    const [, dispatchSwayUser] = useSwayUser();
    const [, dispatchLocale] = useLocale();

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
                const error = new Error(
                    "No user UID returned from provider. Please try closing Sway and logging in again.",
                );
                handleError(error);
            } else if (user.emailVerified === false) {
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
                    .catch(handleError);
            }
        },
        [navigate, dispatchSwayUser, dispatchLocale, sendEmailVerification],
    );

    const handleSigninWithSocialProvider = (provider: EProvider) => {
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
                console.error(error);

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
    };

    return {
        handleUserLoggedIn,
        handleSigninWithSocialProvider,
    };
};
