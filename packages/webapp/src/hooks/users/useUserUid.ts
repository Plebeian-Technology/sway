import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState } from "../../constants/users";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

const userUidSelector = createSelector([userState], (state: IUserState) => state?.user?.uid);

export const useUserUid = (): string | undefined => useSelector(userUidSelector);
