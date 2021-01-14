/** @format */

import { sway } from "sway";
import { createAction } from "@reduxjs/toolkit";

export const setRepresentatives = createAction<sway.ILegislatorWithUserScore[] | null>(
    "userLegislators/set"
);
export const setLegislators = createAction<sway.ILegislator[] | null>(
    "legislators/set"
);
