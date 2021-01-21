/** @format */

import { createReducer } from "@reduxjs/toolkit";
import {
    setLegislators,
    setRepresentatives
} from "../actions/legislatorActions";
const initialState: Record<string, unknown> = {};

export const legislatorReducer = createReducer(initialState, (builder) => {
    builder
        .addCase(setRepresentatives, (state, action) => {
            if (!action.payload) {
                return { ...state };
            }
            return {
                ...state,
                representatives: action.payload.representatives,
                isActive: action.payload.isActive,
            };
        })
        .addCase(setLegislators, (state, action) => {
            return {
                ...state,
                legislators: action?.payload,
            };
        });
});
