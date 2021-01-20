/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { DEFAULT_USER_SETTINGS } from "@sway/constants";
import { useEffect, useState } from "react";
import { useAuthState } from "react-firebase-hooks/auth";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { auth } from "../firebase";

interface IState extends sway.IUserWithSettingsAdmin {
    inviteUid: string;
    locale: sway.ILocale;
}


const userState = (
    state: sway.IAppState,
): IState => {
    return state.userState;
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

export const useInviteUid = () => {
    return useSelector(userState).inviteUid;
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

export const useUserLocale = (): sway.IUserLocale | null => {
    const user = useUser();
    const [userLocale, setUserLocale] = useState<sway.IUserLocale | null>(
        user?.locale || null,
    );

    useEffect(() => {
        const getLocale = async () => {
            if (user?.locale) {
                setUserLocale(user.locale);
            }
        };
        !userLocale && getLocale();
    }, [user, userLocale, setUserLocale]);

    return userLocale;
};
export const useDistrict = (): number => {
    const user = useUser();
    if (user?.locale?.district) return user.locale?.district;

    return 1;
};

export const useSettings = (): sway.IUserSettings => {
    return useSelector(settingsSelector);
};

export const useAdmin = (): boolean => {
    return useSelector(adminSelector);
};
