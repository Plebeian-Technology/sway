/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { CONGRESS_LOCALE, CONGRESS_LOCALE_NAME, SwayStorage } from "@sway/constants";
import { findLocale } from "@sway/utils";
import { useCallback, useEffect, useMemo } from "react";
import { useDispatch, useSelector } from "react-redux";
import { useParams } from "react-router";
import { sway } from "sway";
import { setSwayLocale } from "../redux/actions/localeActions";
import { localSet } from "../utils";

const localeState = (state: sway.IAppState) => {
    return state.locale;
};

const localeSelector = createSelector([localeState], (locale) => locale || CONGRESS_LOCALE);
const localeJSONSelector = createSelector([localeState], (locale) =>
    JSON.stringify(locale || CONGRESS_LOCALE),
);
const localeNameSelector = createSelector(
    [localeState],
    (locale) => locale?.name || CONGRESS_LOCALE_NAME,
);

export const useLocale_JSON = () => {
    return useSelector(localeJSONSelector);
};

export const useLocale = (): [
    sway.IUserLocale | sway.ILocale,
    (userLocale: sway.IUserLocale | sway.ILocale) => void,
] => {
    const params = useParams() as {
        localeName?: string;
    };
    const paramsLocale = useMemo(
        () => (params?.localeName ? findLocale(params.localeName) : undefined),
        [params?.localeName],
    );

    const dispatch = useDispatch();
    const handleSetLocale = useCallback(
        (newLocale: sway.IUserLocale | sway.ILocale) => {
            localSet(SwayStorage.Session.User.Locale, JSON.stringify(newLocale));
            dispatch(setSwayLocale(newLocale));
        },
        [dispatch],
    );

    useEffect(() => {
        if (paramsLocale) {
            handleSetLocale(paramsLocale);
        }
    }, [paramsLocale, handleSetLocale]);

    return [useSelector(localeSelector), handleSetLocale];
};

export const useLocaleName = () => useSelector(localeNameSelector);
