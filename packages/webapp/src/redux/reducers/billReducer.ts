/** @format */

import { createReducer } from "@reduxjs/toolkit";
import { setBillOfTheWeek, setBills } from "../actions/billActions";
const initialState: Record<string, unknown> = {};

export const billReducer = createReducer(initialState, (builder) => {
    builder.addCase(setBillOfTheWeek, (state, action) => {
        return {
            ...state,
            billOfTheWeek: action?.payload?.bill,
            organizationsOfTheWeek: action?.payload?.organizations,
        };
    }).addCase(setBills, (state, action) => {
        return {
            ...state,
            bills: action?.payload,
        };
    });
});
