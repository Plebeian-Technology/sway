/** @format */

import { logDev } from "@sway/utils";
import {
    AuthError,
    GoogleAuthProvider,
    linkWithPopup,
    signInWithPopup,
    signOut,
    UserCredential,
} from "firebase/auth";
import { auth } from "../firebase";
import { handleError } from "../utils";

export const signInWithGoogle = (): Promise<UserCredential | null | void> => {
    const provider = new GoogleAuthProvider();

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("google signin: linking user with google");
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
        logDev("google signin: authing user with google");
        return signInWithPopup(auth, provider);
    }
};
