import { createSelector } from "@reduxjs/toolkit";
import { useMemo } from "react";
import { useAuthState } from "react-firebase-hooks/auth";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState } from "../../sway_constants/users";
import { auth } from "../../firebase";
import { localGet, SWAY_STORAGE } from "../../sway_utils";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const userSelector = createSelector([userState], (state: IUserState) => state?.user);

export const useUser = (): sway.IUser & { isAnonymous: boolean } => {
    const [firebaseUser] = useAuthState(auth);
    const isEmailVerified = useMemo(
        () => firebaseUser?.emailVerified || localGet(SWAY_STORAGE.Local.User.EmailConfirmed),
        [firebaseUser?.emailVerified],
    );

    const swayUser = useSelector(userSelector);

    const fuser = useMemo(
        () =>
            ({
                locales: [] as sway.IUserLocale[],
                uid: firebaseUser?.uid,
                email: firebaseUser?.email,
                name: firebaseUser?.displayName,
                phone: firebaseUser?.phoneNumber,
                isEmailVerified: isEmailVerified,
                isRegistrationComplete: !!localGet(SWAY_STORAGE.Local.User.Registered),
                isAnonymous: !!firebaseUser?.isAnonymous,
                createdAt: firebaseUser?.metadata.creationTime
                    ? new Date(firebaseUser.metadata.creationTime).toLocaleString("en-US")
                    : undefined,
                updatedAt: firebaseUser?.metadata.lastSignInTime
                    ? new Date(firebaseUser.metadata.lastSignInTime).toLocaleString("en-US")
                    : undefined,
            } as sway.IUser),
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
        return {
            ...swayUser,
            ...fuser,
            isAnonymous: false,
            isEmailVerified: swayUser?.isEmailVerified || Boolean(isEmailVerified),
            isRegistrationComplete:
                swayUser?.isRegistrationComplete || !!localGet(SWAY_STORAGE.Local.User.Registered),
        };
    }, [isEmailVerified, swayUser, fuser]);
};
