import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState } from "../../sway_constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const settingsSelector = createSelector(
    [userState],
    (state: sway.IUser) => state?.settings,
);

export const useUserSettings = (): sway.IUserSettings => {
    return useSelector(settingsSelector);
};
