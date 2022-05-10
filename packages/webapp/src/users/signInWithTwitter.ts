/** @format */

import { logDev } from "@sway/utils";
import { AuthError, linkWithPopup, OAuthProvider, signInWithPopup } from "firebase/auth";
import { auth } from "../firebase";
import { handleError } from "../utils";

export const signInWithTwitter = () => {
    const provider = new OAuthProvider("twitter.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("twitter signin: linking user with twitter");
        return linkWithPopup(auth.currentUser, provider).catch((error: AuthError) => {
            if (error.code === "auth/credential-already-in-use") {
                handleError(error, "Please try a different log in method.");
            } else {
                throw error;
            }
        });
    } else {
        logDev("twitter signin: authing user with twitter");
        return signInWithPopup(auth, provider);
    }
};
