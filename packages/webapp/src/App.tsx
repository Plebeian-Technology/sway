/** @format */

import { createMuiTheme, ThemeProvider } from "@material-ui/core";
import { SWAY_CACHING_OKAY_COOKIE } from "@sway/constants";
import { isEmptyObject, IS_DEVELOPMENT, removeTimestamps } from "@sway/utils";
import React from "react";
import { Provider, useDispatch } from "react-redux";
import { sway } from "sway";
import FullScreenLoading from "./components/dialogs/FullScreenLoading";
import SwayNotification from "./components/SwayNotification";
import UserRouter from "./components/user/UserRouter";
import FirebaseCachingConfirmation from "./FirebaseCachingConfirmation";
import { useUserWithSettingsAdmin } from "./hooks";
import { store } from "./redux";
import { setUser } from "./redux/actions/userActions";
import "./scss/bills.scss";
import "./scss/charts.scss";
import "./scss/legislators.scss";
import "./scss/login.scss";
import "./scss/registration.scss";
import {
    handleError,
    isPhoneWidth,
    legisFire,
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
    const userWithSettingsAdmin = useUserWithSettingsAdmin();

    const uid = userWithSettingsAdmin?.user?.uid;

    const _setUser = React.useCallback(
        (_userWithSettingsAdmin: sway.IUserWithSettingsAdmin) => {
            const userLocales = _userWithSettingsAdmin?.user?.locales;

            const u = removeTimestamps(_userWithSettingsAdmin);
            dispatch(
                setUser({
                    user: removeTimestamps(u.user),
                    settings: u.settings,
                    isAdmin: u.isAdmin,
                }),
            );

            if (!isEmptyObject(userLocales)) {
                IS_DEVELOPMENT &&
                    console.log(
                        "APP - USER ALREADY SET. SKIP DISPATCH LOCALE (dev)",
                    );
                return;
            }
        },
        [dispatch],
    );

    const _getUser = React.useCallback(async () => {
        if (!uid) return;
        return await legisFire().users(uid).get();
    }, [uid]);

    React.useEffect(() => {
        const getUser = () => {
            _getUser()
                .then((_userWithSettingsAdmin) => {
                    if (_userWithSettingsAdmin) {
                        _setUser(_userWithSettingsAdmin);
                    }
                })
                .catch(handleError);
        };
        getUser();
    }, [_getUser, _setUser]);

    if (userWithSettingsAdmin.loading) {
        IS_DEVELOPMENT && console.log("APP - LOADING USER (dev)");
        return <FullScreenLoading message={"Loading Sway..."} />;
    }

    return <UserRouter userWithSettingsAdmin={userWithSettingsAdmin} />;
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
            </ThemeProvider>
        </Provider>
    );
};

export default App;
