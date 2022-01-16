/** @format */

import { logDev } from "src/utils";
import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithGoogle = () => {
    const provider = new firebase.auth.GoogleAuthProvider();

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("google signin: linking user with google");
        return auth.currentUser
            .linkWithPopup(provider)
            .catch((error: firebase.auth.AuthError) => {
                if (
                    error.credential &&
                    error.code === "auth/credential-already-in-use"
                ) {
                    return auth.signInWithCredential(error.credential);
                } else {
                    throw error;
                }
            });
    } else {
        logDev("google signin: authing user with google");
        return auth.signInWithPopup(provider);
    }
};
