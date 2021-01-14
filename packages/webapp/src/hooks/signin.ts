/** @format */

import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { useDispatch } from "react-redux";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { useLocale } from "../hooks";
import { setUser } from "../redux/actions/userActions";
import { signInWithApple } from "../users/signinWithApple";
import { signInWithGoogle } from "../users/signInWithGoogle";
import { signInWithTwitter } from "../users/signInWithTwitter";
import {
    handleError,
    IS_DEVELOPMENT,
    legisFire,
    removeTimestamps,
} from "../utils";

export const useSignIn = () => {
    const dispatch = useDispatch();
    const history = useHistory();
    const [, dispatchLocale] = useLocale();

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

    const dispatchUser = (user: sway.IUserWithSettingsAdmin) => {
        dispatch(setUser(user));
    };

    const handleUserLoggedIn = async (result: firebase.default.auth.UserCredential): Promise<string> => {
        const { user } = result;
        const uid = user?.uid;
        if (!uid) return "";

        const userWithSettingsAdmin = await legisFire().users(uid).get();
        const _user: sway.IUser | null | void =
            userWithSettingsAdmin && userWithSettingsAdmin.user;

        if (userWithSettingsAdmin && _user) {
            dispatchUser({
                ...userWithSettingsAdmin,
                user: removeTimestamps(_user),
            });
            if (_user.locale?.name) {
                dispatchLocale({ name: _user?.locale?.name } as sway.ILocale);
            }

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
            isAdmin: false,
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
