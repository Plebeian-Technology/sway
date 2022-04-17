/** @format */

import { createTheme, ThemeProvider } from "@mui/material";
import {
    Collections,
    SWAY_CACHING_OKAY_COOKIE,
    SWAY_SESSION_LOCALE_KEY,
    SWAY_USER_REGISTERED,
} from "@sway/constants";
import {
    getStorage,
    isEmptyObject,
    logDev,
    removeStorage,
    removeTimestamps,
    setStorage,
} from "@sway/utils";
import React, { useCallback, useEffect } from "react";
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
import "./scss/registration.scss";
import { handleError, IS_MOBILE_PHONE, notify, swayDarkBlue, swayFireClient } from "./utils";

const theme = createTheme({
    palette: {
        primary: {
            main: swayDarkBlue,
        },
    },
    typography: {
        fontFamily: [
            "Exo",
            "-apple-system",
            "BlinkMacSystemFont",
            '"Segoe UI"',
            "Roboto",
            '"Helvetica Neue"',
            "Arial",
            "sans-serif",
            '"Apple Color Emoji"',
            '"Segoe UI Emoji"',
            '"Segoe UI Symbol"',
        ].join(","),
    },
    components: {
        MuiInputBase: {
            styleOverrides: {
                root: {
                    color: "inherit",
                },
                input: {
                    color: "inherit",
                },
            },
        },
        MuiFormLabel: {
            styleOverrides: {
                root: {
                    color: "inherit",
                    borderColor: "inherit",
                },
            },
        },
        MuiOutlinedInput: {
            styleOverrides: {
                notchedOutline: {
                    borderColor: "inherit",
                },
            },
        },
        MuiToolbar: {
            styleOverrides: {
                regular: {
                    minHeight: 50,
                },
            },
        },
        MuiDialog: {
            styleOverrides: {
                paper: {
                    margin: IS_MOBILE_PHONE ? "0px" : "32px", // 32px is default
                },
            },
        },
    },
});

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
            getStorage(SWAY_USER_REGISTERED) === "1"
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
                    removeStorage(SWAY_USER_REGISTERED);
                    window.location.href = "/";
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
                            window.location.reload();
                        }, 5000);
                    }
                }, console.error);
        };
        const listener = versionListener();

        return () => listener();
    }, []);

    setStorage(SWAY_CACHING_OKAY_COOKIE, "1");
    removeStorage(SWAY_SESSION_LOCALE_KEY);
    sessionStorage.removeItem(SWAY_SESSION_LOCALE_KEY);

    return (
        <Provider store={store}>
            <ThemeProvider theme={theme}>
                <ToastContainer />
                <Application />
            </ThemeProvider>
        </Provider>
    );
};

export default App;
