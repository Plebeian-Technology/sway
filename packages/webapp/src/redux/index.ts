/** @format */

import { combineReducers, configureStore } from "@reduxjs/toolkit";
import { userReducer } from "./reducers/userReducer";

const reducers = combineReducers({
    user: userReducer,
});

export const store = configureStore({
    reducer: reducers,
    devTools: process.env.NODE_ENV === "development",
});
