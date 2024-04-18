/** @format */

import { configureStore } from "@reduxjs/toolkit";
import { getDefaultSwayLocale } from "../hooks/useLocales";
import { localeReducer } from "./reducers/localeReducer";
import { userReducer } from "./reducers/userReducer";

const reducers = {
    user: userReducer,
    locale: localeReducer,
};

export const store = (() => {
    const _store = {
        reducer: reducers,
        devTools: import.meta.NODE_ENV === "development",
        preloadedState: {
            user: undefined,
            locale: getDefaultSwayLocale(),
        },
    };

    if (import.meta.NODE_ENV === "development") {
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
