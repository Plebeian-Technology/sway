/** @format */

import {
    DEFAULT_USER_SETTINGS,
    ROUTES,
    SWAY_SESSION_LOCALE_KEY,
} from "@sway/constants";
import { isEmptyObject, logDev, removeTimestamps } from "@sway/utils";
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
        logDev("Signin - navigating to route -", route);
        if (!route) return;
        history.push(route);
    };

    const dispatchUser = (user: sway.IUserWithSettings) => {
        dispatch(setUser(user));
    };

    const handleUserLoggedIn = async (
        result: firebase.default.auth.UserCredential,
    ): Promise<undefined | void> => {
        const { user } = result;
        if (!user || isEmptyObject(user)) {
            handleError(
                new Error(
                    `no user from handleUserLoggedIn result, return and skip setting user through dispatch - ${user}`,
                ),
                "No user returned from provider. Please try closing Sway and logging in again.",
            );
            return;
        }

        const uid = user?.uid;
        if (!uid) {
            handleError(
                new Error(
                    `no user.uid from handleUserLoggedIn result, return and skip setting user through dispatch - ${JSON.stringify(
                        user,
                        null,
                        4,
                    )}`,
                ),
                "No user UID returned from provider. Please try closing Sway and logging in again.",
            );
            return;
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
                return;
            }
            if (_user.isRegistrationComplete) {
                logDev("navigate - to legislators after dispatch");
                return;
            }
            logDev("navigate - to registration 1");
            setTimeout(() => {
                handleNavigate(ROUTES.registrationV2);
            }, 1500);
            return;
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
            handleNavigate(ROUTES.registrationV2);
        }, 1500);
        return;
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
                    title: `Signed in with ${provider}.`,
                    duration: 2000,
                });
                return credential;
            })
            .then(handleUserLoggedIn)
            .catch((error) => {
                if (error.code && error.code === "auth/popup-closed-by-user") {
                    handleError(error);
                }
                handleError(error, errorMessage(provider));
            });
    };

    return {
        handleUserLoggedIn,
        handleSigninWithSocialProvider,
    };
};
