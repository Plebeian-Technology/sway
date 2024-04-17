import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState } from "../../sway_constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const userLocalesSelector = createSelector(
    [userState],
    (state: sway.IUserWithSettingsAdmin) => state?.user?.locales || [],
);

export const useUserLocales = (): sway.IUserLocale[] => {
    return useSelector(userLocalesSelector);
};
