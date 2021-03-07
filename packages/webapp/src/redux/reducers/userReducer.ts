/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { DEFAULT_USER_SETTINGS } from "@sway/constants";
import { setInviteUid, setUser } from "../actions/userActions";
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
        .addCase(setInviteUid, (state, action) => {
            return {
                ...state,
                inviteUid: action.payload,
            };
        });
});
