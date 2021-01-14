/** @format */

import firebase from "firebase/app";
import { auth } from "../firebase";

export const signInWithGoogle = () => {
    const provider = new firebase.auth.GoogleAuthProvider();

    return auth.signInWithPopup(provider);
};
