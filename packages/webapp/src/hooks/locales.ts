/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { LOCALES } from "@sway/constants";
import { isEmptyObject } from "@sway/utils";
import { useCallback, useState } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setLocale as setReduxLocale } from "../redux/actions/userActions";

interface IState extends sway.IUserWithSettingsAdmin {
    inviteUid: string;
    locales: sway.ILocale[];
}


const userState = (
    state: sway.IAppState,
): IState => {
    return state.userState;
};

export const localeSelector = createSelector(
    [userState],
    (state: IState) => state?.locales,
)

export const useLocale = (user: sway.IUser | undefined): [
    sway.ILocale,
    (_locale: sway.ILocale) => void,
] => {
    const defaultLocale = !isEmptyObject(user?.locales) && user?.locales[0];
    const [locale, setLocale] = useState<sway.ILocale>(defaultLocale || LOCALES[0]);

    return [locale, setLocale];
};

export const useLocales = (): [
    sway.ILocale[],
    (_locales: sway.ILocale[] | null) => void,
] => {
    const dispatch = useDispatch();
    const dispatchLocale = useCallback(
        (_locales: sway.ILocale[] | null) => {
            dispatch(setReduxLocale(_locales));
        },
        [dispatch],
    );

    return [useSelector(localeSelector), dispatchLocale];
};