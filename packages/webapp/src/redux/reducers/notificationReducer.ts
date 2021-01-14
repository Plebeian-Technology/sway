/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { setNotification } from "../actions/notificationActions";

const initialState: Record<string, unknown> = {};

export const notificationReducer = createReducer(initialState, (builder) => {
    builder.addCase(setNotification, (state, action) => {
        return {
            ...state,
            notification: action.payload
        };
    });
});
