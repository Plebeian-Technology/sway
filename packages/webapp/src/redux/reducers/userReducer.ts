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
            } else {
                return {
                    user: {
                        // @ts-ignore
                        ...state.user,
                        ...action.payload?.user,
                    },
                    settings: {
                        // @ts-ignore
                        ...state.settings,
                        ...action.payload?.settings,
                    },
                    isAdmin: action.payload.isAdmin || state.isAdmin,
                };
            }
        })
        .addCase(setInviteUid, (state, action) => {
            return {
                ...state,
                inviteUid: action.payload,
            };
        });
});
