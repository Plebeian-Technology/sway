/** @format */

import {
    DEFAULT_USER_SETTINGS,
    ROUTES,
    SWAY_SESSION_LOCALE_KEY,
} from "@sway/constants";
import { logDev, removeTimestamps } from "@sway/utils";
import { useDispatch } from "react-redux";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { setUser } from "../redux/actions/userActions";
import { signInWithApple } from "../users/signinWithApple";
import { signInWithGoogle } from "../users/signInWithGoogle";
import { signInWithTwitter } from "../users/signInWithTwitter";
import { handleError, notify, swayFireClient } from "../utils";

export enum EProvider {
    Apple = "Apple",
    Google = "Google",
    Twitter = "Twitter",
}

const errorMessage = (provider: EProvider) =>
    `Error logging in with ${provider}.\n\nDo you already have an account through a different method?`;

export const useSignIn = () => {
    const dispatch = useDispatch();
    const history = useHistory();

    logDev("Clear locale in Sway session storage");
    sessionStorage.removeItem(SWAY_SESSION_LOCALE_KEY);

    const handleNavigate = (route: string | undefined) => {
        if (!route) return;
        history.push(route);
    };

    const dispatchUser = (user: sway.IUserWithSettings) => {
        dispatch(setUser(user));
    };

    const handleUserLoggedIn = async (
        result: firebase.default.auth.UserCredential,
    ): Promise<string> => {
        const { user } = result;
        if (!user) {
            logDev(
                "no user from handleUserLoggedIn result, return empty string and skip user dispatch",
            );
            return "";
        }

        const uid = user?.uid;
        if (!uid) {
            logDev(
                "no uid from handleUserLoggedIn, return empty string and skip user dispatch",
            );
            return "";
        }

        if (user.emailVerified === false) {
            notify({
                level: "info",
                title: "Please verify your email.",
                message: "Click/tap 'Resend Activation Email' if needed.",
            });
        }

        const userWithSettings = await swayFireClient()
            .users(uid)
            .getWithSettings();

        if (userWithSettings?.user) {
            const _user: sway.IUser | null | void = {
                ...userWithSettings?.user,
                isEmailVerified: Boolean(user?.emailVerified),
            };

            dispatchUser({
                ...userWithSettings,
                user: removeTimestamps(_user),
            });
            if (_user.isRegistrationComplete && !_user.isEmailVerified) {
                logDev(
                    "navigate - user registered but email not verified, navigate to to signin",
                );
                return "";
            }
            if (_user.isRegistrationComplete) {
                logDev("navigate - to legislators");
                return "";
            }
            logDev("navigate - to registration 1");
            setTimeout(() => {
                handleNavigate(ROUTES.registrationIntroduction);
            }, 1000);
            return "";
        }

        logDev("navigate - to registration 2 - no user in userWithSettings");
        dispatchUser({
            user: {
                email: user.email,
                uid: uid,
                isEmailVerified: user.emailVerified,
                isRegistrationComplete: false,
            } as sway.IUser,
            settings: DEFAULT_USER_SETTINGS,
        });

        setTimeout(() => {
            handleNavigate(ROUTES.registrationIntroduction);
        }, 1000);
        return "";
    };

    const handleSigninWithSocialProvider = (provider: EProvider) => {
        logDev("handleSigninWithSocialProvider with provider -", provider);
        const method = {
            [EProvider.Google]: signInWithGoogle,
            [EProvider.Apple]: signInWithApple,
            [EProvider.Twitter]: signInWithTwitter,
        }[provider];

        method()
            .then((credential: firebase.default.auth.UserCredential) => {
                notify({
                    level: "success",
                    title: `Signed In with ${provider}.`,
                    message: "Navigating to Sway registration page.",
                    duration: 2000,
                });
                return credential;
            })
            .then(handleUserLoggedIn)
            .catch((error) => {
                if (error.code && error.code === "auth/popup-closed-by-user") {
                    return;
                }
                handleError(error, errorMessage(provider));
            });
    };

    return {
        handleUserLoggedIn,
        handleSigninWithSocialProvider,
    };
};
