/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { DEFAULT_USER_SETTINGS } from "@sway/constants";
import { IS_DEVELOPMENT } from "@sway/utils";
import { useAuthState } from "react-firebase-hooks/auth";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { auth } from "../firebase";

interface IState extends sway.IUserWithSettings {
    inviteUid: string;
    userLocales: sway.IUserLocale[];
}

const userState = (state: sway.IAppState): IState => {
    return state.user;
};

const userSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettings) => state?.user,
);
const settingsSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettings) => state?.settings,
);

export const useUserSettings = (): sway.IUserSettings => {
    return useSelector(settingsSelector);
};

export const useInviteUid = (): string => {
    return useSelector(userState)?.inviteUid;
};

export const useUserLocales = (): sway.IUserLocale[] => {
    return useSelector(userState)?.userLocales;
};

export const useSwayUser = (): sway.IUser => {
    return useSelector(userState).user;
};

export const useUserWithSettings = (): sway.IUserWithSettings & {
    loading: boolean;
} => {
    const [user, loading] = useAuthState(auth);
    const swayUserWithSettings = useSelector(userState);

    if (!user || user.isAnonymous) {
        IS_DEVELOPMENT &&
            console.log(
                "(dev) Returning null or anon-user with default settings.",
            );
        return {
            // eslint-disable-next-line
            // @ts-ignore
            user: user,
            settings: DEFAULT_USER_SETTINGS,
            loading,
        };
    }
    if (!swayUserWithSettings || !swayUserWithSettings.user) {
        IS_DEVELOPMENT &&
            console.log(
                "(dev) Returning firebase user with undefined isRegistrationComplete",
            );
        return {
            // eslint-disable-next-line
            // @ts-ignore
            user: {
                ...user,
                // eslint-disable-next-line
                // @ts-ignore
                isRegistrationComplete: undefined,
            },
            settings: DEFAULT_USER_SETTINGS,
            loading,
        };
    }

    const swayUser = swayUserWithSettings.user;
    if (!swayUser?.isRegistrationComplete) {
        IS_DEVELOPMENT &&
            console.log(
                "(dev) Returning user with isRegistrationComplete === false and default settings.",
            );
        return {
            // eslint-disable-next-line
            // @ts-ignore
            user: {
                ...user,
                isRegistrationComplete: false,
            },
            settings: DEFAULT_USER_SETTINGS,
            loading,
        };
    }
    IS_DEVELOPMENT &&
        console.log(
            "(dev) Returning logged-in user with isRegistrationComplete === true",
        );
    return {
        user: {
            ...swayUser,
            ...user?.metadata,
        },
        settings: swayUserWithSettings.settings,
        loading,
    };
};

export const useUser = (): sway.IUser & { loading: boolean } => {
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

export const useDistrict = (): string => {
    // TODO: FIX USE DISTRICT

    return "1";
};
