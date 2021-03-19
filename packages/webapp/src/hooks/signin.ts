/** @format */

import {
    DEFAULT_USER_SETTINGS,
    ROUTES,
    SWAY_SESSION_LOCALE_KEY,
} from "@sway/constants";
import { IS_DEVELOPMENT, removeTimestamps } from "@sway/utils";
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

const handleGoogleSignin = (
    callback: (result: firebase.default.auth.UserCredential) => Promise<string>,
) => {
    signInWithGoogle()
        .then(callback)
        .catch((error) => {
            if (error.code && error.code === "auth/popup-closed-by-user") {
                return;
            }
            handleError(error, errorMessage(EProvider.Google));
        });
};

const handleAppleSignin = (
    callback: (result: firebase.default.auth.UserCredential) => Promise<string>,
) => {
    signInWithApple()
        .then(callback)
        .catch((error) => {
            if (error.code && error.code === "auth/popup-closed-by-user") {
                return;
            }
            handleError(error, errorMessage(EProvider.Apple));
        });
};

const handleTwitterSignin = (
    callback: (result: firebase.default.auth.UserCredential) => Promise<string>,
) => {
    signInWithTwitter()
        .then(callback)
        .catch((error) => {
            if (error.code && error.code === "auth/popup-closed-by-user") {
                return;
            }
            handleError(error, errorMessage(EProvider.Twitter));
        });
};

export const useSignIn = () => {
    const dispatch = useDispatch();
    const history = useHistory();

    IS_DEVELOPMENT && console.log("(dev) Clear locale in Sway session storage");
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
        if (!user) return "";

        const uid = user?.uid;
        if (!uid) return "";

        if (user.emailVerified === false) {
            notify({
                level: "info",
                message: "Please verify your email. Click/tap 'Resend Activation Email' if needed.",
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
                IS_DEVELOPMENT &&
                    console.log(
                        "(dev) navigate - user registered but email not verified, navigate to to signin",
                    );
                return "";
            }
            if (_user.isRegistrationComplete) {
                IS_DEVELOPMENT && console.log("(dev) navigate - to legislators");
                // return ROUTES.legislators;
                return "";
            }
            IS_DEVELOPMENT && console.log("(dev) navigate - to registration 1");
            handleNavigate(ROUTES.registrationIntroduction);
            return "";
        }

        IS_DEVELOPMENT && console.log("(dev) navigate - to registration 2");
        dispatchUser({
            user: {
                email: user.email,
                uid: user.uid,
                isEmailVerified: false,
                isRegistrationComplete: false,
            } as sway.IUser,
            settings: DEFAULT_USER_SETTINGS,
        });
        handleNavigate(ROUTES.registrationIntroduction);
        return "";
    };

    const handleSigninWithSocialProvider = (provider: EProvider) => {
        switch (provider) {
            case EProvider.Apple: {
                handleAppleSignin(handleUserLoggedIn);
                break;
            }
            case EProvider.Google: {
                handleGoogleSignin(handleUserLoggedIn);
                break;
            }
            case EProvider.Twitter: {
                handleTwitterSignin(handleUserLoggedIn);
                break;
            }

            default: {
                break;
            }
        }
    };

    return {
        handleUserLoggedIn,
        handleSigninWithSocialProvider,
    };
};
