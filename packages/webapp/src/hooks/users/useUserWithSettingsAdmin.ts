import { DEFAULT_USER_SETTINGS } from "@sway/constants";
import { logDev } from "@sway/utils";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { localGet, SWAY_STORAGE, removeTimestamps } from "../../utils";
import { IUserState } from "../../constants/users";
import { useFirebaseUser } from "./useFirebaseUser";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

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
