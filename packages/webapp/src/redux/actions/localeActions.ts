import { sway } from "sway";
import { createAction } from "@reduxjs/toolkit";

export const setSwayLocale = createAction<sway.ILocale | sway.IUserLocale | undefined>(
    "locale/set",
);
