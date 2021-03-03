/** @format */

import { DEFAULT_USER_SETTINGS, ROUTES, SWAY_SESSION_LOCALE_KEY } from "@sway/constants";
import {
    IS_DEVELOPMENT,
    removeTimestamps
} from "@sway/utils";
import { useDispatch } from "react-redux";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { setUser } from "../redux/actions/userActions";
import { signInWithApple } from "../users/signinWithApple";
import { signInWithGoogle } from "../users/signInWithGoogle";
import { signInWithTwitter } from "../users/signInWithTwitter";
import {
    handleError,
    swayFireClient
} from "../utils";

export const useSignIn = () => {
    const dispatch = useDispatch();
    const history = useHistory();

    IS_DEVELOPMENT && console.log("(dev) Clear locale in Sway session storage");
    sessionStorage.removeItem(SWAY_SESSION_LOCALE_KEY);

    const handleNavigate = (route: string | undefined) => {
        if (!route) return;
        history.push(route);
    };

    const errorMessage = (provider: string) =>
        `Error logging in with ${provider}.\n\nDo you already have an account through a different method?`;
    const handleGoogleSignin = () => {
        signInWithGoogle()
            .then(handleUserLoggedIn)
            .catch((error) => {
                if (error.code && error.code === "auth/popup-closed-by-user") {
                    return;
                }
                handleError(error, errorMessage("Google"));
            });
    };

    const handleAppleSignin = () => {
        signInWithApple()
            .then(handleUserLoggedIn)
            .catch((error) => {
                if (error.code && error.code === "auth/popup-closed-by-user") {
                    return;
                }
                handleError(error, errorMessage("Apple"));
            });
    };

    const handleTwitterSignin = () => {
        signInWithTwitter()
            .then(handleUserLoggedIn)
            .catch((error) => {
                if (error.code && error.code === "auth/popup-closed-by-user") {
                    return;
                }
                handleError(error, errorMessage("Twitter"));
            });
    };

    const dispatchUser = (user: sway.IUserWithSettings) => {
        dispatch(setUser(user));
    };

    const handleUserLoggedIn = async (result: firebase.default.auth.UserCredential): Promise<string> => {
        const { user } = result;
        const uid = user?.uid;
        if (!uid) return "";

        const userWithSettings = await swayFireClient().users(uid).getWithSettings();
        const _user: sway.IUser | null | void =
            userWithSettings && userWithSettings.user;

        if (userWithSettings && _user) {
            dispatchUser({
                ...userWithSettings,
                user: removeTimestamps(_user),
            });

            if (_user.isRegistrationComplete) {
                IS_DEVELOPMENT && console.log("to legislators (dev)");
                // return ROUTES.legislators;
                return "";
            }
            IS_DEVELOPMENT && console.log("to registration 1 (dev)");
            handleNavigate(ROUTES.registrationIntroduction);
            return "";
        }

        IS_DEVELOPMENT && console.log("to registration 2 (dev)");
        const payload = user?.email
            ? {
                  email: user?.email,
                  uid: user?.uid,
              }
            : { uid: user?.uid };
        const u = payload as sway.IUser;
        dispatchUser({
            user: u,
            settings: DEFAULT_USER_SETTINGS,
        });
        handleNavigate(ROUTES.registrationIntroduction);
        return "";
    };

    return {
        handleUserLoggedIn,
        handleGoogleSignin,
        handleAppleSignin,
        handleTwitterSignin,
    }
};
