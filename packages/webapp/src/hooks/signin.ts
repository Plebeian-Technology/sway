/** @format */

import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { isEmptyObject, logDev, removeTimestamps } from "@sway/utils";
import { AuthError, UserCredential } from "firebase/auth";
import { omit } from "lodash";
import { useDispatch } from "react-redux";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { setUser } from "../redux/actions/userActions";
import { signInWithApple } from "../users/signinWithApple";
import { signInWithGoogle } from "../users/signInWithGoogle";
import { signInWithTwitter } from "../users/signInWithTwitter";
import { handleError, notify, swayFireClient } from "../utils";
import { useEmailVerification } from "./useEmailVerification";
import { NON_SERIALIZEABLE_FIREBASE_FIELDS } from "./users";

// eslint-disable-next-line
export enum EProvider {
    Apple = "Apple",
    Google = "Google",
    Twitter = "Twitter",
}

const errorMessage = (provider: EProvider) =>
    `Error logging in with ${provider}.\n\nDo you already have an account through a different method?`;

export const useSignIn = () => {
    const dispatch = useDispatch();
    const navigate = useNavigate();
    const { sendEmailVerification } = useEmailVerification();

    const dispatchUser = (user: sway.IUserWithSettingsAdmin) => {
        dispatch(setUser(omit(user, NON_SERIALIZEABLE_FIREBASE_FIELDS)));
    };

    const handleUserLoggedIn = async (result: UserCredential | void): Promise<undefined | void> => {
        const user = result?.user;

        logDev("signin.handleUserLoggedIn.user -", { user });

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
        }

        const userWithSettings = await swayFireClient().users(uid).getWithSettings();

        if (userWithSettings?.user) {
            const _user: sway.IUser | null | void = {
                ...userWithSettings?.user,
                isEmailVerified: Boolean(user?.emailVerified),
            };

            dispatchUser({
                ...userWithSettings,
                user: removeTimestamps(_user),
            });

            setTimeout(() => {
                if (_user.isRegistrationComplete && !_user.isEmailVerified) {
                    logDev(
                        "signin.handleUserLoggedIn - user.isRegistrationComplete && !user.isEmailVerified - NO ACTION",
                    );
                } else if (!_user.isRegistrationComplete && _user.isEmailVerified) {
                    logDev(
                        "signin.handleUserLoggedIn - !user.isRegistrationComplete && user.isEmailVerified - GO TO REGISTRATION",
                    );
                    navigate(ROUTES.registration, { replace: true });
                } else if (!_user.isRegistrationComplete && !_user.isEmailVerified) {
                    logDev(
                        "signin.handleUserLoggedIn - !user.isRegistrationComplete && !user.isEmailVerified - GO TO REGISTRATION",
                    );
                    navigate(ROUTES.registration, { replace: true });
                } else if (_user.isRegistrationComplete && _user.isEmailVerified) {
                    logDev(
                        "signin.handleUserLoggedIn - user.isRegistrationComplete && user.isEmailVerified - GO TO LEGISLATORS",
                    );
                    navigate(ROUTES.legislators, { replace: true });
                }
            }, 500);
        } else {
            logDev("navigate - to registration 2 - no user in userWithSettings");
            dispatchUser({
                user: {
                    email: user.email,
                    uid: uid,
                    isEmailVerified: user.emailVerified,
                    isRegistrationComplete: false,
                } as sway.IUser,
                settings: DEFAULT_USER_SETTINGS,
                isAdmin: false,
            });

            setTimeout(() => {
                navigate(ROUTES.registration, { replace: true });
            }, 1500);
        }
    };

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
