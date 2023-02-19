import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState } from "../../constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const adminSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.isAdmin,
);

export const useAdmin = (): boolean => {
    return useSelector(adminSelector);
};
