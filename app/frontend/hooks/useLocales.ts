/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { CONGRESS_LOCALE } from "app/frontend/sway_constants";
import { findLocale, isEmptyObject } from "app/frontend/sway_utils";
import { useCallback, useEffect, useMemo } from "react";
import { useDispatch, useSelector } from "react-redux";
import { useParams } from "react-router";
import { sway } from "sway";
import { setSwayLocale } from "../redux/actions/localeActions";
import { sessionGet, sessionSet, SWAY_STORAGE } from "../sway_utils";

export const getDefaultSwayLocale = () => {
    const sessionLocale = sessionGet(SWAY_STORAGE.Session.User.Locale);
    if (sessionLocale) {
        return JSON.parse(sessionLocale);
    }

    const query = new URLSearchParams(window.location.search);
    const queryLocale = query && query.get("locale");
    if (queryLocale) {
        return findLocale(queryLocale);
    }

    return CONGRESS_LOCALE;
};

const localeState = (state: sway.IAppState) => {
    return state.locale;
};

const localeSelector = createSelector([localeState], (locale) => locale || getDefaultSwayLocale());
const localeJSONSelector = createSelector([localeState], (locale) =>
    JSON.stringify(locale || isEmptyObject(locale) ? getDefaultSwayLocale() : locale),
);
const localeNameSelector = createSelector(
    [localeState],
    (locale) => locale?.name || getDefaultSwayLocale().name,
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
            sessionSet(SWAY_STORAGE.Session.User.Locale, JSON.stringify(newLocale));
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
