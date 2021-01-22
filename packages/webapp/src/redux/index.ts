/** @format */

import { combineReducers, configureStore } from "@reduxjs/toolkit";
import { billReducer } from "./reducers/billReducer";
import { legislatorReducer } from "./reducers/legislatorReducer";
import { notificationReducer } from "./reducers/notificationReducer";
import { userReducer } from "./reducers/userReducer";



const reducers = combineReducers({
    bills: billReducer,
    user: userReducer,
    legislators: legislatorReducer,
    notification: notificationReducer,
});



export const store = configureStore({
    reducer: reducers,
    devTools: process.env.NODE_ENV === "development",
});
