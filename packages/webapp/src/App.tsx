/** @format */

import { createMuiTheme, ThemeProvider } from "@material-ui/core";
import {
    SWAY_CACHING_OKAY_COOKIE,
    SWAY_SESSION_LOCALE_KEY,
} from "@sway/constants";
import { isEmptyObject, IS_DEVELOPMENT, removeTimestamps } from "@sway/utils";
import React, { useCallback, useEffect } from "react";
import { Provider, useDispatch } from "react-redux";
import { sway } from "sway";
import FullScreenLoading from "./components/dialogs/FullScreenLoading";
import SwayNotification from "./components/SwayNotification";
import UserRouter from "./components/user/UserRouter";
import FirebaseCachingConfirmation from "./FirebaseCachingConfirmation";
import { useUserWithSettings } from "./hooks";
import { store } from "./redux";
import { setUser } from "./redux/actions/userActions";
import "./scss/bills.scss";
import "./scss/charts.scss";
import "./scss/checkbox.scss";
import "./scss/legislators.scss";
import "./scss/login.scss";
import "./scss/registration.scss";
import {
    handleError,
    IS_MOBILE_PHONE,
    swayDarkBlue,
    swayFireClient,
} from "./utils";

const theme = createMuiTheme({
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
    overrides: {
        MuiInputBase: {
            root: {
                color: "inherit",
            },
            input: {
                color: "inherit",
            },
        },
        MuiFormLabel: {
            root: {
                color: "inherit",
                borderColor: "inherit",
            },
        },
        MuiOutlinedInput: {
            notchedOutline: {
                borderColor: "inherit",
            },
        },
        MuiToolbar: {
            regular: {
                minHeight: 50,
            },
        },
        MuiDialog: {
            paper: {
                margin: IS_MOBILE_PHONE ? "0px" : "32px", // 32px is default
            },
        },
    },
});

const Application = () => {
    const dispatch = useDispatch();
    const userWithSettings = useUserWithSettings();

    const uid = userWithSettings?.user?.uid;

    const _setUser = useCallback(
        (_userWithSettings: sway.IUserWithSettings) => {
            const userLocales = _userWithSettings?.user?.locales;
            const u = removeTimestamps(_userWithSettings);
            dispatch(
                setUser({
                    user: removeTimestamps(u.user),
                    settings: u.settings,
                }),
            );

            if (!isEmptyObject(userLocales)) {
                IS_DEVELOPMENT &&
                    console.log(
                        "(dev) APP - User already set. Skip dispatch locale",
                    );
                return;
            }
        },
        [dispatch],
    );

    const _getUser = useCallback(async () => {
        if (!uid) return;
        return await swayFireClient().users(uid).getWithSettings();
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

    if (userWithSettings.loading) {
        IS_DEVELOPMENT && console.log("(dev) APP - Loading user");
        return <FullScreenLoading message={"Loading Sway..."} />;
    }
    IS_DEVELOPMENT && console.log("(dev) APP - Rendering router");
    return <UserRouter userWithSettings={userWithSettings} />;
};

const App = () => {
    const isPersisted: string | null = localStorage.getItem(
        SWAY_CACHING_OKAY_COOKIE,
    );
    localStorage.removeItem(SWAY_SESSION_LOCALE_KEY);
    sessionStorage.removeItem(SWAY_SESSION_LOCALE_KEY);

    const enablePersistence = (enable: boolean) => {
        if (!enable) {
            console.log("Caching Disabled.");
            localStorage.setItem(SWAY_CACHING_OKAY_COOKIE, "0");
        } else {
            console.log("Caching Enabled.");
            localStorage.setItem(SWAY_CACHING_OKAY_COOKIE, "1");
        }
        window.location.reload();
    };

    if (isPersisted === null) {
        return (
            <FirebaseCachingConfirmation
                enablePersistence={enablePersistence}
            />
        );
    }

    return (
        <Provider store={store}>
            <ThemeProvider theme={theme}>
                <SwayNotification />
                <Application />
            </ThemeProvider>
        </Provider>
    );
};

export default App;
