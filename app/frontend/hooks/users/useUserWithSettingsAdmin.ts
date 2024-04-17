import { DEFAULT_USER_SETTINGS } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { localGet, SWAY_STORAGE, removeTimestamps } from "../../sway_utils";
import { IUserState } from "../../sway_constants/users";
import { useFirebaseUser } from "./useFirebaseUser";
import { useMemo } from "react";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

type TReturnUser = sway.IUserWithSettingsAdmin & {
    loading: boolean;
};

export const useUserWithSettingsAdmin = (): TReturnUser => {
    const [firebaseUser, loading] = useFirebaseUser();
    const swayUserWithSettings = useSelector(userState);

    return useMemo(() => {
        const isLocalLoggedIn = !!localGet(SWAY_STORAGE.Local.User.SignedIn);
        const isLocalEmailConfirmed = !!localGet(SWAY_STORAGE.Local.User.EmailConfirmed);
        const isLocalRegistered = !!localGet(SWAY_STORAGE.Local.User.Registered);

        if (
            !firebaseUser ||
            (firebaseUser.isAnonymous && !isLocalLoggedIn) ||
            (!isLocalLoggedIn && (!swayUserWithSettings || !swayUserWithSettings.user))
        ) {
            logDev("Returning null or anon-user with default settings.");
            return removeTimestamps({
                user: {
                    uid: firebaseUser?.uid,
                    email: firebaseUser?.email,
                    name: firebaseUser?.displayName,
                    phone: firebaseUser?.phoneNumber,
                    isAnonymous: firebaseUser?.isAnonymous,
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
                loading,
            } as TReturnUser);
        } else {
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
                    createdAt: firebaseUser?.metadata.creationTime
                        ? new Date(firebaseUser.metadata.creationTime).toLocaleString("en-US")
                        : undefined,
                    updatedAt: firebaseUser?.metadata.lastSignInTime
                        ? new Date(firebaseUser.metadata.lastSignInTime).toLocaleString("en-US")
                        : undefined,
                    isEmailVerified: firebaseUser.emailVerified || isLocalEmailConfirmed,
                    isRegistrationComplete: isLocalRegistered,
                    isAnonymous: firebaseUser?.isAnonymous,
                },
                settings: swayUserWithSettings.settings || DEFAULT_USER_SETTINGS,
                isAdmin: !!swayUserWithSettings.isAdmin,
                loading,
            } as TReturnUser);
        }
    }, [firebaseUser, loading, swayUserWithSettings]);
};
