/** @format */

import { configureStore } from "@reduxjs/toolkit";
import { getDefaultSwayLocale } from "../hooks/useLocales";
import { localeReducer } from "./reducers/localeReducer";
import { userReducer } from "./reducers/userReducer";
import { IS_DEVELOPMENT } from "app/frontend/sway_constants";

import { logger as reduxLogger } from "redux-logger";

const reducers = {
    user: userReducer,
    locales: localeReducer,
};

export const store = (initialState: Record<string, any>) => {
    const _store = {
        reducer: reducers,
        devTools: IS_DEVELOPMENT,
        preloadedState: {
            user: initialState.user,
            locales: {
                locales: [],
                locale: getDefaultSwayLocale()
            },
            // userLegislators: initialState.legislators || []
        },
    };

    return configureStore({
        ..._store,
        middleware: () => [reduxLogger] as any,
    });
};
