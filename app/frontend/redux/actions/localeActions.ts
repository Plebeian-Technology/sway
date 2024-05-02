import { sway } from "sway";
import { createAction } from "@reduxjs/toolkit";

export const setSwayLocales = createAction<sway.ISwayLocale[]>(
    "locales/set",
);
export const setSwayLocale = createAction<sway.ISwayLocale | undefined>(
    "locale/set",
);
