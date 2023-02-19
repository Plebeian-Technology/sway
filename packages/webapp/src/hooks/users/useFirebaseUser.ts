import { User } from "firebase/auth";
import { useAuthState } from "react-firebase-hooks/auth";
import { auth } from "../../firebase";

export const useFirebaseUser = (): [User | null | undefined, boolean, Error | undefined] => {
    return useAuthState(auth);
};
