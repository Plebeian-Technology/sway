/** @format */

import { Collections, SwayStorage } from "@sway/constants";
import { isEmptyObject, logDev, removeTimestamps } from "@sway/utils";
import { useCallback, useEffect } from "react";
import { Provider, useDispatch } from "react-redux";
import { ToastContainer } from "react-toastify";
import "react-toastify/dist/ReactToastify.css";
import { sway } from "sway";
import FullScreenLoading from "./components/dialogs/FullScreenLoading";
import UserRouter from "./components/user/UserRouter";
import { firestore } from "./firebase";
import { useUserWithSettingsAdmin } from "./hooks";
import { store } from "./redux";
import { setUser } from "./redux/actions/userActions";
import "./scss/bills.scss";
import "./scss/charts.scss";
import "./scss/checkbox.scss";
import "./scss/login.scss";
import "./scss/main.scss";
import "./scss/registration.scss";
import "./scss/votes.scss";
import { handleError, localGet, localRemove, localSet, notify, swayFireClient } from "./utils";

// eslint-disable-next-line
const isFirebaseUser = (user: any) => {
    return Boolean(user.metadata);
};

const Application = () => {
    const dispatch = useDispatch();
    const userWithSettings = useUserWithSettingsAdmin();

    const uid = userWithSettings?.user?.uid;

    const _setUser = useCallback(
        (_userWithSettings: sway.IUserWithSettingsAdmin) => {
            const userLocales = userWithSettings?.user?.locales;
            if (!isEmptyObject(userLocales)) {
                logDev("APP - User already set. Skip dispatch locale");
                return;
            }

            const u = removeTimestamps(_userWithSettings);
            logDev("APP - Dispatching setUser -", _userWithSettings);
            dispatch(
                setUser({
                    user: removeTimestamps(u.user),
                    settings: u.settings,
                    isAdmin: _userWithSettings.isAdmin,
                }),
            );
        },
        [dispatch],
    );

    const _getUser = useCallback(async () => {
        if (!uid) return;
        return swayFireClient().users(uid).getWithSettings();
    }, [uid]);

    useEffect(() => {
        const getUser = () => {
            _getUser()
                .then((_userWithSettings) => {
                    if (_userWithSettings) {
                        _setUser(_userWithSettings);
                    }
                })
                .catch(handleError);
        };
        getUser();
    }, [_getUser, _setUser]);

    const isLoadingPreviouslyAuthedUser = (
        _uid: string,
        _userWithSettings: sway.IUserWithSettings,
    ) => {
        return (
            _uid &&
            isFirebaseUser(_userWithSettings.user) &&
            _userWithSettings.user.isAnonymous === false &&
            _userWithSettings.user.isRegistrationComplete === undefined &&
            localGet(SwayStorage.Local.User.Registered) === "1"
        );
    };

    const isLoading =
        userWithSettings.loading || isLoadingPreviouslyAuthedUser(uid, userWithSettings);

    useEffect(() => {
        logDev("APP - Set loading timeout.");
        const timeout = setTimeout(() => {
            if (isLoading) {
                notify({
                    level: "error",
                    title: "Loading app timed out. Refreshing.",
                });
                setTimeout(() => {
                    localRemove(SwayStorage.Local.User.Registered);
                    window.location.replace("/");
                }, 2000);
            }
        }, 10000);
        return () => {
            logDev("APP - Clear loading timeout.");
            clearTimeout(timeout);
        };
    }, [isLoading]);

    if (isLoading) {
        logDev("APP - Loading user");
        return <FullScreenLoading message={"Loading Sway..."} />;
    }
    logDev("APP - Rendering router");
    return <UserRouter userWithSettingsAdmin={userWithSettings} />;
};

const App = () => {
    useEffect(() => {
        const version = process.env.REACT_APP_SWAY_VERSION;
        console.log(`(prod) Setting listener to see if Sway version ${version} is current.`);

        const versionListener = () => {
            console.log("(prod) Running Sway version check.");

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
                            window.location.reload();
                        }, 5000);
                    }
                }, console.error);
        };
        const listener = versionListener();

        return () => listener();
    }, []);

    localSet(SwayStorage.Local.User.FirebaseCaching, "1");

    return (
        <Provider store={store}>
            <ToastContainer />
            <Application />
        </Provider>
    );
};

export default App;
