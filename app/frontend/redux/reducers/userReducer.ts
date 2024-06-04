/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { setInviteUid, setUser } from "../actions/userActions";

const initialState: Record<string, unknown> = {};

export const userReducer = createReducer(initialState, (builder) => {
    builder
        .addCase(setUser, (_state, action) => {
            return action.payload ?? undefined;
        })
        .addCase(setInviteUid, (state, action) => {
            return {
                ...state,
                inviteUid: action.payload,
            };
        });
});
