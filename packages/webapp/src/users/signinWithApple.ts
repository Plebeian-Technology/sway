/** @format */

import { logDev } from "@sway/utils";
import {
    AuthError,
    linkWithPopup,
    OAuthProvider,
    signInWithPopup,
    signOut,
    UserCredential,
} from "firebase/auth";
import { auth } from "../firebase";
import { handleError } from "../utils";

export const signInWithApple = (): Promise<UserCredential | null | void> => {
    const provider = new OAuthProvider("apple.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("apple signin: linking user with apple");
        return linkWithPopup(auth.currentUser, provider).catch((error: AuthError) => {
            if (error.code === "auth/credential-already-in-use" && auth.currentUser) {
                handleError(error, "Please refresh the page and try again.");
                return signOut(auth)
                    .then(() => {
                        localStorage.clear();
                        sessionStorage.clear();
                    })
                    .catch(handleError);
            } else {
                signOut(auth)
                    .then(() => {
                        localStorage.clear();
                        sessionStorage.clear();
                    })
                    .catch(handleError);
                throw error;
            }
        });
    } else {
        logDev("apple signin: authing user with apple");
        return signInWithPopup(auth, provider);
    }
};
