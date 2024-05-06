import { createSelector } from "@reduxjs/toolkit";
import { useSelector } from "react-redux";
import { sway } from "sway";

const appState = (state: sway.IAppState): sway.IAppState => {
    return state;
};

const userSelector = createSelector([appState], (state: sway.IAppState) => state.user);

export const useUser = (): sway.IUser => {
    return useSelector(userSelector);
};
