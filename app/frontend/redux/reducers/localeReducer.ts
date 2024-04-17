/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { setSwayLocale } from "../actions/localeActions";

const initialState = {};

export const localeReducer = createReducer(initialState, (builder) => {
    builder.addCase(setSwayLocale, (state, action) => {
        return action.payload;
    });
});
