/** @format */

import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithApple = () => {
    const provider = new firebase.auth.OAuthProvider("apple.com");
    provider.addScope("email");
    provider.setCustomParameters({
        locale: "en",
    });

    return auth.signInWithPopup(provider);
};
