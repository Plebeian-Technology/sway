/** @format */


import { createAction } from "@reduxjs/toolkit";
import { sway } from "sway";

export const setNotification = createAction<sway.ISwayNotification | null>(
    "notification/set"
);