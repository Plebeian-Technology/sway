/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { useCallback } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setLocale } from "../redux/actions/userActions";

interface IState extends sway.IUserWithSettingsAdmin {
    inviteUid: string;
    locale: sway.ILocale;
}


const userState = (
    state: sway.IAppState,
): IState => {
    return state.userState;
};

export const localeSelector = createSelector(
    [userState],
    (state: IState) => state?.locale,
)

export const useLocale = (): [
    sway.ILocale,
    (_locale: sway.ILocale | null) => void,
] => {
    const dispatch = useDispatch();
    const dispatchLocale = useCallback(
        (_locale: sway.ILocale | null) => {
            dispatch(setLocale(_locale));
        },
        [dispatch],
    );

    return [useSelector(localeSelector), dispatchLocale];
};