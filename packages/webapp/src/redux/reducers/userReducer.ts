/** @format */

import { createReducer } from "@reduxjs/toolkit";
import {
    DEFAULT_USER_SETTINGS,
    SWAY_SESSION_LOCALE_KEY
} from "@sway/constants";
import { setInviteUid, setLocale, setUser } from "../actions/userActions";
const initialState: Record<string, unknown> = {};

export const userReducer = createReducer(initialState, (builder) => {
    builder
        .addCase(setUser, (state, action) => {
            if (!action.payload) {
                return {
                    ...state,
                    user: null,
                    settings: DEFAULT_USER_SETTINGS,
                };
            }
            return {
                ...state,
                ...action?.payload,
            };
        })
        .addCase(setLocale, (state, action) => {
            action.payload && localStorage.setItem(
                SWAY_SESSION_LOCALE_KEY,
                JSON.stringify(action.payload),
            );
            return {
                ...state,
                locale: action.payload,
            };
        })
        .addCase(setInviteUid, (state, action) => {
            return {
                ...state,
                inviteUid: action.payload,
            };
        });
});
