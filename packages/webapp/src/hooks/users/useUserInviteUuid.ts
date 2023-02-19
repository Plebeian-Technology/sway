import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState } from "../../constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const selector = createSelector([userState], (state) => state?.inviteUid || "");

export const useUserInviteUuid = (): string => {
    return useSelector(selector);
};
