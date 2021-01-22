/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { DEFAULT_USER_SETTINGS } from "@sway/constants";
import { useAuthState } from "react-firebase-hooks/auth";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { auth } from "../firebase";

interface IState extends sway.IUserWithSettingsAdmin {
    inviteUid: string;
    userLocales: sway.IUserLocale[];
}

const userState = (
    state: sway.IAppState,
): IState => {
    return state.user;
};

const userSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.user,
);
const adminSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.isAdmin,
);
const settingsSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.settings,
);

export const useSettings = (): sway.IUserSettings => {
    return useSelector(settingsSelector);
};

export const useAdmin = (): boolean => {
    return useSelector(adminSelector);
};

export const useInviteUid = (): string => {
    return useSelector(userState)?.inviteUid;
};
export const useUserLocales = (): sway.IUserLocale[] => {
    return useSelector(userState)?.userLocales;
};

export const useUserWithSettingsAdmin = (): sway.IUserWithSettingsAdmin & {
    loading: boolean;
} => {
    const [user, loading] = useAuthState(auth);
    const swayUserWithSettingsAdmin = useSelector(userState);

    if (!user || user.isAnonymous) {
        return {
            user: user,
            isAdmin: false,
            settings: DEFAULT_USER_SETTINGS,
            loading,
        };
    }
    if (!swayUserWithSettingsAdmin || !swayUserWithSettingsAdmin.user) {
        return {
            user: {
                ...user,
                isRegistrationComplete: false,
            },
            isAdmin: false,
            settings: DEFAULT_USER_SETTINGS,
            loading,
        };
    }

    const swayUser = swayUserWithSettingsAdmin.user;
    if (!swayUser?.isRegistrationComplete) {
        return {
            ...user,
            isRegistrationComplete: false,
            loading,
        };
    }
    return {
        user: {
            ...swayUser,
            ...user?.metadata,
        },
        settings: swayUserWithSettingsAdmin.settings,
        isAdmin: swayUserWithSettingsAdmin.isAdmin,
        loading,
    };
};

export const useUser = (): (sway.IUser & { loading: boolean }) => {
    const [user, loading] = useAuthState(auth);
    const swayUser: sway.IUser = useSelector(userSelector);

    if (
        swayUser?.isRegistrationComplete ||
        swayUser?.isRegistrationComplete === false
    ) {
        return {
            ...swayUser,
            ...user?.metadata,
            loading,
        };
    }

    // eslint-disable-next-line
    // @ts-ignore
    return { ...user, loading };
};


export const useDistrict = (): number => {
    // TODO: FIX USE DISTRICT

    return 1;
};
