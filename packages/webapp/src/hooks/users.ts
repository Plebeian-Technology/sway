/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { DEFAULT_USER_SETTINGS, SwayStorage } from "@sway/constants";
import { logDev } from "@sway/utils";
import { signOut, User } from "firebase/auth";
import { useCallback } from "react";
import { useAuthState } from "react-firebase-hooks/auth";
import { useSelector } from "react-redux";
import { useNavigate } from "react-router";
import { sway } from "sway";
import { auth } from "../firebase";
import { handleError, localRemove } from "../utils";

export const NON_SERIALIZEABLE_FIREBASE_FIELDS = [
    "accessToken",
    "auth",
    "proactiveRefresh",
    "providerData",
    "providerId",
    "reloadListener",
    "reloadUserInfo",
    "stsTokenManager",
    "tenantId",
];

interface IState extends sway.IUserWithSettingsAdmin {
    inviteUid: string;
    isEmailVerifiedRedux: boolean;
    userLocales: sway.IUserLocale[];
}

const userState = (state: sway.IAppState): IState => {
    return state.user;
};

const userSelector = createSelector([userState], (state: IState) => state?.user);

const settingsSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.settings,
);

const adminSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.isAdmin,
);

export const useAdmin = (): boolean => {
    return useSelector(adminSelector);
};

export const useUserSettings = (): sway.IUserSettings => {
    return useSelector(settingsSelector);
};

export const useInviteUid = (): string => {
    const selector = createSelector([userState], (state) => state.inviteUid);
    return useSelector(selector);
};

export const useUserLocales = (): sway.IUserLocale[] => {
    return useSelector(userState)?.userLocales;
};

export const useFirebaseUser = (): [User | null | undefined, boolean, Error | undefined] => {
    return useAuthState(auth);
};

export const useUserWithSettingsAdmin = (): sway.IUserWithSettingsAdmin & {
    loading: boolean;
} => {
    const [firebaseUser, loading] = useFirebaseUser();
    const swayUserWithSettings = useSelector(userState);

    if (!firebaseUser || firebaseUser.isAnonymous) {
        logDev("Returning null or anon-user with default settings.");
        return {
            // eslint-disable-next-line
            // @ts-ignore
            user: firebaseUser,
            settings: DEFAULT_USER_SETTINGS,
            isAdmin: false,
            loading,
        };
    }
    if (!swayUserWithSettings || !swayUserWithSettings.user) {
        logDev("Returning firebase user with undefined isRegistrationComplete");
        return {
            // eslint-disable-next-line
            // @ts-ignore
            user: {
                ...firebaseUser,
                isEmailVerified: firebaseUser.emailVerified,
                // eslint-disable-next-line
                // @ts-ignore
                isRegistrationComplete: undefined,
            },
            settings: DEFAULT_USER_SETTINGS,
            isAdmin: false,
            loading,
        };
    }

    const swayUser = swayUserWithSettings.user;
    if (swayUser.isRegistrationComplete === undefined) {
        logDev("Returning user with isRegistrationComplete === false and default settings.");
        return {
            // eslint-disable-next-line
            // @ts-ignore
            user: {
                ...firebaseUser,
                isEmailVerified: firebaseUser.emailVerified,
                isRegistrationComplete: false,
            },
            settings: DEFAULT_USER_SETTINGS,
            isAdmin: false,
            loading,
        };
    }
    logDev(
        `Returning logged-in user with isRegistrationComplete === ${swayUserWithSettings.user?.isRegistrationComplete}, isEmailVerified = ${swayUserWithSettings.user?.isEmailVerified}, isAdmin -`,
        swayUserWithSettings.isAdmin,
    );

    return {
        user: {
            ...swayUser,
            ...firebaseUser?.metadata,
            isEmailVerified: firebaseUser.emailVerified,
        },
        settings: swayUserWithSettings.settings,
        isAdmin: swayUserWithSettings.isAdmin,
        loading,
    };
};

export const useUser = (): sway.IUser & { loading: boolean } => {
    const [firebaseUser, loading] = useAuthState(auth);
    const swayUser: sway.IUser = useSelector(userSelector);

    const fuser = {
        uid: firebaseUser?.uid,
        email: firebaseUser?.email,
        name: firebaseUser?.displayName,
        phone: firebaseUser?.phoneNumber,
        isEmailVerified: firebaseUser?.emailVerified,
        createdAt: firebaseUser?.metadata.creationTime
            ? new Date(firebaseUser.metadata.creationTime).toLocaleString("en-US")
            : undefined,
        updatedAt: firebaseUser?.metadata.lastSignInTime
            ? new Date(firebaseUser.metadata.lastSignInTime).toLocaleString("en-US")
            : undefined,
    } as sway.IUser;

    if (swayUser?.isRegistrationComplete || swayUser?.isRegistrationComplete === false) {
        return {
            ...swayUser,
            ...fuser,
            loading,
        };
    }

    // eslint-disable-next-line
    // @ts-ignore
    return {
        ...fuser,
        isEmailVerified: Boolean(firebaseUser && firebaseUser.emailVerified),
        loading,
    };
};

export const useLogout = () => {
    const navigate = useNavigate();
    return useCallback(() => {
        signOut(auth)
            .then(() => {
                localRemove(SwayStorage.Local.User.Registered);
                navigate("/", { replace: true });
            })
            .catch(handleError);
    }, [navigate]);
};
