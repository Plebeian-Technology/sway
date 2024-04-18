/** @format */

import { configureStore } from "@reduxjs/toolkit";
import { getDefaultSwayLocale } from "../hooks/useLocales";
import { localeReducer } from "./reducers/localeReducer";
import { userReducer } from "./reducers/userReducer";
import { IS_DEVELOPMENT } from "app/frontend/sway_constants";

const reducers = {
    user: userReducer,
    locale: localeReducer,
};

export const store = (() => {
    const _store = {
        reducer: reducers,
        devTools: IS_DEVELOPMENT,
        preloadedState: {
            user: undefined,
            locale: getDefaultSwayLocale(),
        },
    };


    return configureStore({
        ..._store,
        // middleware: () => [] as any[],
    });
    // if (IS_DEVELOPMENT) {
    //     // eslint-disable-next-line
    //     const { logger } = require("redux-logger");
    //     return configureStore({
    //         ..._store,
    //         middleware: [logger],
    //     });
    // } else {
    //     return configureStore({
    //         ..._store,
    //         middleware: [],
    //     });
    // }
})();
