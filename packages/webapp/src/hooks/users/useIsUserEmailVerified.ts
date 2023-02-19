import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { localGet, SWAY_STORAGE } from "../../utils";
import { IUserState } from "../../constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const isUserEmailVerifiedSelector = createSelector(
    [userState],
    (state: IUserState) =>
        state?.user?.isEmailVerified || !!localGet(SWAY_STORAGE.Local.User.EmailConfirmed),
);

export const useIsUserEmailVerified = (): boolean => useSelector(isUserEmailVerifiedSelector);
