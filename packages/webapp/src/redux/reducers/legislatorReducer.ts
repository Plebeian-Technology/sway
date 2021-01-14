/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { setLegislators, setRepresentatives } from "../actions/legislatorActions";
const initialState: Record<string, unknown> = {};

export const legislatorReducer = createReducer(initialState, (builder) => {
    builder.addCase(setRepresentatives, (state, action) => {
        return {
            ...state,
            representatives: action.payload,
        };
    }).addCase(setLegislators, (state, action) => {
        return {
            ...state,
            legislators: action?.payload,
        };
    });
});
