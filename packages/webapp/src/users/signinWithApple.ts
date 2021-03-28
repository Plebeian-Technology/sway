/** @format */

import { logDev } from "@sway/utils";
import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithApple = () => {
    const provider = new firebase.auth.OAuthProvider("apple.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("apple signin: linking user with apple");
        return auth.currentUser.linkWithPopup(provider);
    } else {
        logDev("apple signin: authing user with apple");
        return auth.signInWithPopup(provider);
    }
};
