/** @format */

import { combineReducers, configureStore } from "@reduxjs/toolkit";
import { notificationReducer } from "./reducers/notificationReducer";
import { userReducer } from "./reducers/userReducer";

const reducers = combineReducers({
    user: userReducer,
    notification: notificationReducer,
});

export const store = configureStore({
    reducer: reducers,
    devTools: process.env.NODE_ENV === "development",
});
