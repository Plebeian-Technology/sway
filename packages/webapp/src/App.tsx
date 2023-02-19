/** @format */

import { Collections } from "@sway/constants";
import { logDev } from "@sway/utils";
import { useEffect, useState } from "react";
import { Provider } from "react-redux";
import { ToastContainer } from "react-toastify";
import FullScreenLoading from "./components/dialogs/FullScreenLoading";
import UserRouter from "./components/user/UserRouter";
import { firestore } from "./firebase";
import { store } from "./redux";
import {
    handleError,
    IS_TAURI,
    localRemove,
    localSet,
    notify,
    removeTimestamps,
    SWAY_STORAGE,
} from "./utils";
import { useLocale } from "./hooks/useLocales";
import { useSwayFireClient } from "./hooks/useSwayFireClient";
import { useFirebaseUser, useSwayUser } from "./hooks/useUsers";

// eslint-disable-next-line
const getIsFirebaseUser = (user: any) => {
    return Boolean(user.metadata);
};

const versionListener = () => {
    console.log("(prod) Running Sway version check.");
    const version = process.env.REACT_APP_SWAY_VERSION;
    console.log(`(prod) Setting listener to see if Sway version ${version} is current.`);

    return firestore
        .collection(Collections.SwayVersion)
        .doc("current")
        .onSnapshot((snap) => {
            const fireVersion = snap.data()?.version;
            console.log("(prod) Retrieved Sway current version -", fireVersion);
            if (!version || Number(fireVersion) > Number(version)) {
                console.log("(prod) Reloading Sway due to version out-of-date.");
                notify({
                    level: "info",
                    title: "A new version of Sway is available.",
                    message: "Reloading.",
                });
                setTimeout(() => {
                    logDev("RELOAD SWAY");
                    window?.location?.reload && window.location.reload();
                }, 5000);
            }
        }, console.error);
};

const Application = () => {
    const fire = useSwayFireClient();
    const [firebaseUser] = useFirebaseUser();

    const [, dispatchSwayUser] = useSwayUser();
    const [, dispatchSwayLocale] = useLocale();

    const [isLoading, setLoading] = useState<boolean>(true);

    useEffect(() => {
        if (!firebaseUser?.uid || !firebaseUser?.emailVerified) {
            setLoading(false);
            return;
        }

        fire.users(firebaseUser?.uid)
            .getWithSettings()
            .then((u) => {
                setLoading(false);
                if (!u) return;

                logDev("APP - Dispatching setUser -", u);
                dispatchSwayUser({
                    user: removeTimestamps(u.user),
                    settings: u.settings,
                    isAdmin: u.isAdmin,
                });
            })
            .catch((e) => {
                setLoading(false);
                handleError(e);
            });
    }, [
        fire,
        firebaseUser?.uid,
        firebaseUser?.emailVerified,
        dispatchSwayLocale,
        dispatchSwayUser,
    ]);

    useEffect(() => {
        logDev("APP - Set loading timeout.");
        const timeout = setTimeout(() => {
            if (isLoading) {
                notify({
                    level: "error",
                    title: "Loading app timed out. Refreshing.",
                });
                setTimeout(() => {
                    localRemove(SWAY_STORAGE.Local.User.SignedIn);
                    localRemove(SWAY_STORAGE.Local.User.EmailConfirmed);
                    localRemove(SWAY_STORAGE.Local.User.Registered);
                    window.location.replace("/");
                }, 2000);
            }
        }, 15000);
        return () => {
            logDev("APP - Clear loading timeout.");
            clearTimeout(timeout);
        };
    }, [isLoading]);

    if (isLoading) {
        logDev("APP - Loading user");
        return <FullScreenLoading message={"Loading Sway..."} />;
    } else {
        logDev("APP - Rendering router");
        return <UserRouter />;
    }
};

const App = () => {
    useEffect(() => {
        if (IS_TAURI) return;
        const listener = versionListener();
        return () => listener();
    }, []);

    localSet(SWAY_STORAGE.Local.User.FirebaseCaching, "1");

    return (
        <Provider store={store}>
            <ToastContainer />
            <Application />
        </Provider>
    );
};

export default App;
