/** @format */

import { configureStore } from "@reduxjs/toolkit";
import { SwayStorage } from "@sway/constants";
import { findLocale } from "@sway/utils";
import { localGet } from "../utils";
import { localeReducer } from "./reducers/localeReducer";
import { userReducer } from "./reducers/userReducer";

const reducers = {
    user: userReducer,
    locale: localeReducer,
};

export const store = (() => {
    const _store = {
        reducer: reducers,
        devTools: process.env.NODE_ENV === "development",
        preloadedState: {
            user: undefined,
            locale: (() => {
                const locale = localGet(SwayStorage.Session.User.Locale);
                if (locale) {
                    return JSON.parse(locale);
                }
                const query = new URLSearchParams(window.location.search);
                const queryLocale = query && query.get("locale");
                if (queryLocale) {
                    return findLocale(queryLocale);
                }

                return undefined;
            })(),
        },
    };

    if (process.env.NODE_ENV === "development") {
        // eslint-disable-next-line
        const { logger } = require("redux-logger");
        return configureStore({
            ..._store,
            middleware: [logger],
        });
    } else {
        return configureStore({
            ..._store,
            middleware: [],
        });
    }
})();
