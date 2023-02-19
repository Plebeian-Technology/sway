/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { DEFAULT_USER_SETTINGS } from "@sway/constants";
import { logDev } from "@sway/utils";
import { signOut, User } from "firebase/auth";
import { omit } from "lodash";
import { useCallback, useMemo } from "react";
import { useAuthState } from "react-firebase-hooks/auth";
import { useDispatch, useSelector } from "react-redux";
import { useNavigate } from "react-router";
import { sway } from "sway";
import { auth } from "../firebase";
import { setUser } from "../redux/actions/userActions";
import { handleError, localGet, removeTimestamps, SWAY_STORAGE } from "../utils";

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
    "createdAt",
    "updatedAt",
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

const userUidSelector = createSelector([userState], (state: IState) => state?.user?.uid);
const isUserEmailVerifiedSelector = createSelector(
    [userState],
    (state: IState) =>
        state?.user?.isEmailVerified || !!localGet(SWAY_STORAGE.Local.User.EmailConfirmed),
);
const isUserRegistrationCompleteSelector = createSelector(
    [userState],
    (state: IState) =>
        !!state?.user?.isRegistrationComplete || !!localGet(SWAY_STORAGE.Local.User.Registered),
);

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
    return useSelector(userState)?.userLocales || [];
};

export const useFirebaseUser = (): [User | null | undefined, boolean, Error | undefined] => {
    return useAuthState(auth);
};

export const useSwayUser = (): [
    sway.IUserWithSettingsAdmin,
    (newUser: sway.IUserWithSettingsAdmin) => void,
] => {
    const dispatch = useDispatch();
    const setSwayUser = useCallback(
        (newUser: sway.IUserWithSettingsAdmin) => {
            if (newUser) {
                dispatch(setUser(omit(newUser, NON_SERIALIZEABLE_FIREBASE_FIELDS)));
            }
        },
        [dispatch],
    );

    return [useSelector(userState), setSwayUser];
};

export const useUserUid = (): string | undefined => useSelector(userUidSelector);

export const useIsUserEmailVerified = (): boolean => useSelector(isUserEmailVerifiedSelector);

export const useIsUserRegistrationComplete = (): boolean =>
    useSelector(isUserRegistrationCompleteSelector);

export const useUserWithSettingsAdmin = (): sway.IUserWithSettingsAdmin & {
    loading: boolean;
} => {
    const [firebaseUser, loading] = useFirebaseUser();
    const swayUserWithSettings = useSelector(userState);

    // @ts-ignore
    return useMemo(() => {
        const isLocalLoggedIn = !!localGet(SWAY_STORAGE.Local.User.SignedIn);
        const isLocalEmailConfirmed = !!localGet(SWAY_STORAGE.Local.User.EmailConfirmed);
        const isLocalRegistered = !!localGet(SWAY_STORAGE.Local.User.Registered);

        if (!firebaseUser || (firebaseUser.isAnonymous && !isLocalLoggedIn)) {
            logDev("Returning null or anon-user with default settings.");
            return removeTimestamps({
                user: {
                    uid: firebaseUser?.uid,
                    email: firebaseUser?.email,
                    name: firebaseUser?.displayName,
                    phone: firebaseUser?.phoneNumber,
                    isEmailVerified: Boolean(firebaseUser?.emailVerified) || isLocalEmailConfirmed,
                    isRegistrationComplete: isLocalRegistered,
                    createdAt: firebaseUser?.metadata.creationTime
                        ? new Date(firebaseUser.metadata.creationTime).toLocaleString("en-US")
                        : undefined,
                    updatedAt: firebaseUser?.metadata.lastSignInTime
                        ? new Date(firebaseUser.metadata.lastSignInTime).toLocaleString("en-US")
                        : undefined,
                },
                settings: DEFAULT_USER_SETTINGS,
                isAdmin: false,
            });
        }

        if (!isLocalLoggedIn && (!swayUserWithSettings || !swayUserWithSettings.user)) {
            logDev("Returning firebase user with undefined isRegistrationComplete");
            return removeTimestamps({
                user: {
                    ...firebaseUser,
                    isEmailVerified: firebaseUser.emailVerified || isLocalEmailConfirmed,
                    isRegistrationComplete: isLocalRegistered,
                },
                settings: DEFAULT_USER_SETTINGS,
                isAdmin: false,
                loading,
            });
        }

        const swayUser = swayUserWithSettings.user;

        logDev(
            `Returning logged-in user with isRegistrationComplete === ${
                swayUserWithSettings.user?.isRegistrationComplete || isLocalRegistered
            }, isEmailVerified = ${
                swayUserWithSettings.user?.isEmailVerified || isLocalEmailConfirmed
            }, isAdmin -`,
            swayUserWithSettings.isAdmin,
        );

        return removeTimestamps({
            user: {
                ...swayUser,
                ...firebaseUser?.metadata,
                isEmailVerified: firebaseUser.emailVerified || isLocalEmailConfirmed,
                isRegistrationComplete: isLocalRegistered,
            },
            settings: swayUserWithSettings.settings || DEFAULT_USER_SETTINGS,
            isAdmin: !!swayUserWithSettings.isAdmin,
            loading,
        });
    }, [firebaseUser, loading, swayUserWithSettings]);
};

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
