/** @format */

import { createAction } from "@reduxjs/toolkit";
import { sway } from "sway";

interface IUpdateObject {
    representatives: sway.ILegislatorWithUserScore[];
    isActive: boolean;
}

export const setRepresentatives = createAction<IUpdateObject | null>(
    "userLegislators/set"
);
export const setLegislators = createAction<sway.ILegislator[] | null>(
    "legislators/set"
);
