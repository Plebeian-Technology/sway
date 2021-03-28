/** @format */

import { logDev } from "@sway/utils";
import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithTwitter = () => {
    const provider = new firebase.auth.OAuthProvider("twitter.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    if (auth.currentUser && auth.currentUser.isAnonymous) {
        logDev("twitter signin: linking user with twitter");
        return auth.currentUser.linkWithPopup(provider);
    } else {
        logDev("twitter signin: authing user with twitter");
        return auth.signInWithPopup(provider);
    }
};
