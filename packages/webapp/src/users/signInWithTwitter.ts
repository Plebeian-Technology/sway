/** @format */

import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithTwitter = () => {
    const provider = new firebase.auth.OAuthProvider("twitter.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    return auth.signInWithPopup(provider);
};
