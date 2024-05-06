import { sway } from "sway";
import { createAction } from "@reduxjs/toolkit";

export const setUser = createAction<Partial<sway.IUser> | null>("user/set");
export const setInviteUid = createAction<string>("invite/set");
