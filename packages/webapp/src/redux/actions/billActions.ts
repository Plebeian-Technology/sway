/** @format */

import { sway } from "sway";
import { createAction } from "@reduxjs/toolkit";

export const setBillOfTheWeek = createAction<sway.IBillWithOrgs | null>(
    "botw/set"
);
export const setBills = createAction<sway.IBillWithOrgs[] | null>(
    "bills/set"
);
