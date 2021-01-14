/** @format */

import { createMuiTheme, ThemeProvider } from "@material-ui/core";
import {
    LOCAL_STORAGE_LOCALE_KEY,
    SWAY_CACHING_OKAY_COOKIE,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import React from "react";
import { Provider, useDispatch } from "react-redux";
import { sway } from "sway";
import FullScreenLoading from "./components/dialogs/FullScreenLoading";
import SwayNotification from "./components/SwayNotification";
import UserRouter from "./components/user/UserRouter";
import { firestore } from "./firebase";
import FirebaseCachingConfirmation from "./FirebaseCachingConfirmation";
import { useLocale, useUserWithSettingsAdmin } from "./hooks";
import { store } from "./redux";
import { setUser } from "./redux/actions/userActions";
import "./scss/bills.scss";
import "./scss/charts.scss";
import "./scss/legislators.scss";
import "./scss/login.scss";
import "./scss/registration.scss";
import {
    isPhoneWidth,
    IS_DEVELOPMENT,
    legisFire,
    removeTimestamps,
    swayBlack,
    swayDarkBlue,
    swayWhite,
} from "./utils";

const theme = createMuiTheme({
    palette: {
        primary: {
            main: swayDarkBlue,
        },
    },
    overrides: {
        MuiInputBase: {
            input: {
                color: swayWhite,
            },
        },
        MuiFormLabel: {
            root: {
                color: swayWhite,
                "&$focused": {
                    color: swayBlack,
                },
            },
        },
        MuiOutlinedInput: {
            notchedOutline: {
                color: swayWhite,
                borderColor: swayWhite,
            },
        },
        MuiDialog: {
            paper: {
                margin: isPhoneWidth ? "0px" : "32px", // 32px is default
            },
        },
    },
});

const Application = () => {
    const dispatch = useDispatch();
    const [locale, setLocale] = useLocale();
    const userWithSettingsAdmin = useUserWithSettingsAdmin();

    const uid = userWithSettingsAdmin?.user?.uid;

    const _setUser = React.useCallback(
        (_userWithSettingsAdmin: sway.IUserWithSettingsAdmin) => {
            const _locale = locale as sway.IUserLocale;
            const userLocale = _userWithSettingsAdmin?.user?.locale;

            const u = removeTimestamps(_userWithSettingsAdmin);
            dispatch(
                setUser({
                    user: removeTimestamps(u.user),
                    settings: u.settings,
                    isAdmin: u.isAdmin,
                }),
            );

            if (
                userLocale?.name === _locale.name &&
                userLocale?.district === _locale?.district
            ) {
                IS_DEVELOPMENT &&
                    console.log("APP - USER ALREADY SET. SKIP DISPATCH LOCALE (dev)");
                return;
            }
            if (locale) {
                setLocale({
                    ...locale,
                    ...userLocale,
                });
            } else {
                setLocale(userLocale || null);
            }
        },
        [dispatch, setLocale, locale],
    );

    const dispatchLocale = React.useCallback(() => {
        if (locale?.name) return;

        IS_DEVELOPMENT && console.log("APP - DISPATCHING LOCALE (dev)");
        const storedLocale = localStorage.getItem(LOCAL_STORAGE_LOCALE_KEY);
        const _locale = storedLocale && JSON.parse(storedLocale);
        if (_locale && _locale.name) {
            IS_DEVELOPMENT && console.log("APP - DISPATCH STORAGE LOCALE (dev)");
            setLocale(_locale);
            return;
        }
        SwayFireClient.Locales(firestore).then((locales) => {
            IS_DEVELOPMENT && console.log("APP - DISPATCH DEFAULT LOCALE (dev)");
            setLocale(locales[0]);
        }).catch(console.error);
    }, [setLocale, locale]);

    const _getUser = React.useCallback(async () => {
        if (!uid) return;
        return await legisFire().users(uid).get();
    }, [uid]);

    React.useEffect(() => {
        const getUser = () => {
            _getUser().then((_userWithSettingsAdmin) => {
                if (_userWithSettingsAdmin) {
                    _setUser(_userWithSettingsAdmin);
                } else {
                    dispatchLocale();
                }
            }).catch(console.error);
        };
        getUser();
    }, [_getUser, _setUser, dispatchLocale]);

    if (!locale?.name) {
        IS_DEVELOPMENT && console.log("APP - LOADING NO LOCALE NAME (dev)");
        return <FullScreenLoading message={"Loading Sway..."} />;
    }
    if (userWithSettingsAdmin.loading) {
        IS_DEVELOPMENT && console.log("APP - LOADING USER (dev)");
        return <FullScreenLoading message={"Loading Sway..."} />;
    }
    if (
        locale.name &&
        locale.name &&
        userWithSettingsAdmin?.user?.locale?.name && locale.name !==
            userWithSettingsAdmin.user.locale.name
    ) {
        IS_DEVELOPMENT && console.log("APP - LOADING LOCALE MISMATCH (dev)");
        return <FullScreenLoading message={"Loading Sway..."} />;
    }

    return (
        <UserRouter
            locale={locale}
            userWithSettingsAdmin={userWithSettingsAdmin}
        />
    );
};

const App = () => {
    const cookie: string | null = localStorage.getItem(
        SWAY_CACHING_OKAY_COOKIE,
    );

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

    if (cookie === null) {
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
                <div id="recaptcha" />
            </ThemeProvider>
        </Provider>
    );
};

export default App;
