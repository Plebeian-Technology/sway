/** @format */

import { logDev } from "@sway/utils";
import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithGoogle = () => {
    const provider = new firebase.auth.GoogleAuthProvider();

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("google signin: linking user with google");
        return auth.currentUser.linkWithPopup(provider);
    } else {
        logDev("google signin: authing user with google");
        return auth.signInWithPopup(provider);
    }
};
