/** @format */

import { configureStore } from "@reduxjs/toolkit";
import { sway } from "sway";
import { userReducer } from "./reducers/userReducer";

export interface IAppState {
    user: sway.IUserWithSettingsAdmin & { inviteUid: string };
}

const reducers = {
    user: userReducer,
};

export const store = configureStore({
    reducer: reducers,
    devTools: process.env.NODE_ENV === "development",
});
