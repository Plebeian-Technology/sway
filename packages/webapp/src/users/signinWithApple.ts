/** @format */

import { logDev } from "@sway/utils";
import { AuthError, linkWithPopup, OAuthProvider, signInWithPopup } from "firebase/auth";
import { auth } from "../firebase";
import { handleError } from "../utils";

export const signInWithApple = () => {
    const provider = new OAuthProvider("apple.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("apple signin: linking user with apple");
        return linkWithPopup(auth.currentUser, provider).catch((error: AuthError) => {
            if (error.code === "auth/credential-already-in-use") {
                handleError(error, "Please try a different log in method.");
            } else {
                throw error;
            }
        });
    } else {
        logDev("apple signin: authing user with apple");
        return signInWithPopup(auth, provider);
    }
};
