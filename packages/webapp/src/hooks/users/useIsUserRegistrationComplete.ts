import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { localGet, SWAY_STORAGE } from "../../utils";
import { IUserState } from "../../constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const isUserRegistrationCompleteSelector = createSelector(
    [userState],
    (state: IUserState) =>
        !!state?.user?.isRegistrationComplete || !!localGet(SWAY_STORAGE.Local.User.Registered),
);

export const useIsUserRegistrationComplete = (): boolean =>
    useSelector(isUserRegistrationCompleteSelector);
