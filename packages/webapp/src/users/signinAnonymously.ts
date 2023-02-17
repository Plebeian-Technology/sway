import { signInAnonymously, UserCredential } from "firebase/auth";
import { auth } from "../firebase";

export const anonymousSignIn = async (): Promise<UserCredential | undefined> => {
    return signInAnonymously(auth);
};
