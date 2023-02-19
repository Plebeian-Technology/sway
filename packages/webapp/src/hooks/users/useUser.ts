import { createSelector } from "@reduxjs/toolkit";
import { signOut } from "firebase/auth";
import { useMemo, useCallback } from "react";
import { useAuthState } from "react-firebase-hooks/auth";
import { useSelector } from "react-redux";
import { useNavigate } from "react-router";
import { sway } from "sway";
import { auth } from "../../firebase";
import { handleError } from "../../utils";
import { IUserState } from "../../constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const userSelector = createSelector([userState], (state: IUserState) => state?.user);

export const useUser = (): sway.IUser & { isAnonymous: boolean } => {
    const [firebaseUser] = useAuthState(auth);
    const isEmailVerified = useMemo(
        () => firebaseUser?.emailVerified,
        [firebaseUser?.emailVerified],
    );

    const swayUser = useSelector(userSelector);

    const fuser = useMemo(
        () => ({
            locales: [] as sway.IUserLocale[],
            uid: firebaseUser?.uid,
            email: firebaseUser?.email,
            name: firebaseUser?.displayName,
            phone: firebaseUser?.phoneNumber,
            isEmailVerified: isEmailVerified,
            isAnonymous: !!firebaseUser?.isAnonymous,
            createdAt: firebaseUser?.metadata.creationTime
                ? new Date(firebaseUser.metadata.creationTime).toLocaleString("en-US")
                : undefined,
            updatedAt: firebaseUser?.metadata.lastSignInTime
                ? new Date(firebaseUser.metadata.lastSignInTime).toLocaleString("en-US")
                : undefined,
        }),
        [
            firebaseUser?.uid,
            firebaseUser?.email,
            firebaseUser?.displayName,
            firebaseUser?.phoneNumber,
            firebaseUser?.isAnonymous,
            isEmailVerified,
            firebaseUser?.metadata.creationTime,
            firebaseUser?.metadata.lastSignInTime,
        ],
    ) as sway.IUser & { isAnonymous: boolean };

    return useMemo(() => {
        if (swayUser?.isRegistrationComplete || swayUser?.isRegistrationComplete === false) {
            return {
                ...swayUser,
                ...fuser,
                isAnonymous: false,
            };
        } else {
            return {
                ...fuser,
                isEmailVerified: Boolean(isEmailVerified),
            };
        }
    }, [isEmailVerified, swayUser, fuser]);
};

export const useLogout = () => {
    const navigate = useNavigate();
    return useCallback(() => {
        signOut(auth)
            .then(() => {
                localStorage.clear();
                sessionStorage.clear();
                navigate("/", { replace: true });
            })
            .catch(handleError);
    }, [navigate]);
};
