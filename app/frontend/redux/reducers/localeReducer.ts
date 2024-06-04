/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { setSwayLocale, setSwayLocales } from "../actions/localeActions";
import { sway } from "sway";

const initialState = {
    locales: [] as sway.ISwayLocale[],
    locale: undefined as sway.ISwayLocale | undefined,
};

export const localeReducer = createReducer(initialState, (builder) => {
    builder
        .addCase(setSwayLocales, (state, action) => {
            return {
                ...state,
                locales: action.payload || [],
            };
        })
        .addCase(setSwayLocale, (state, action) => {
            return {
                ...state,
                locale: action.payload,
            };
        });
});
