/** @format */

import { logDev } from "@sway/utils";
import { AuthError, GoogleAuthProvider, linkWithPopup, signInWithPopup } from "firebase/auth";
import { auth } from "../firebase";
import { handleError } from "../utils";

export const signInWithGoogle = () => {
    const provider = new GoogleAuthProvider();

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("google signin: linking user with google");
        return linkWithPopup(auth.currentUser, provider).catch((error: AuthError) => {
            if (error.code === "auth/credential-already-in-use") {
                handleError(error, "Please try a different log in method.");
            } else {
                throw error;
            }
        });
    } else {
        logDev("google signin: authing user with google");
        return signInWithPopup(auth, provider);
    }
};
