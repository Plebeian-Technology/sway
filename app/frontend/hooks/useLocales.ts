/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { useCallback, useEffect } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setSwayLocale, setSwayLocales } from "../redux/actions/localeActions";
import { SWAY_STORAGE, sessionGet, sessionSet } from "../sway_utils";

export const getDefaultSwayLocale = () => {
    const sessionLocale = sessionGet(SWAY_STORAGE.Session.User.Locale);
    if (sessionLocale) {
        return JSON.parse(sessionLocale);
    }

    // return CONGRESS_LOCALE;
};

const localeState = (state: sway.IAppState) => {
    return state.locales;
};

const localesSelector = createSelector([localeState], (locale) => locale?.locales || []);
const localeSelector = createSelector([localeState], (locale) => locale?.locale || getDefaultSwayLocale());
const localeNameSelector = createSelector([localeState], (locale) => (locale?.locale || getDefaultSwayLocale()).name);

export const useLocaleName = () => useSelector(localeNameSelector);

export const useLocales = () => {
    const dispatch = useDispatch();
    const { get } = useAxiosGet<sway.ISwayLocale[]>("/sway_locales", { skipInitialRequest: true });

    useEffect(() => {
        get()
            .then((items) => {
                if (items) {
                    dispatch(setSwayLocales(items as sway.ISwayLocale[]));
                }
            })
            .catch(console.error);
    }, [dispatch, get]);

    return [useSelector(localesSelector)];
};

export const useLocale = (initialSwayLocale?: sway.ISwayLocale): [sway.ISwayLocale, (id?: number) => void] => {
    const dispatch = useDispatch();

    const params = new URLSearchParams(window.location.search) as {
        localeName?: string;
    };

    useEffect(() => {
        if (initialSwayLocale) {
            dispatch(setSwayLocale(initialSwayLocale as sway.ISwayLocale));
        }
    }, [dispatch, initialSwayLocale])

    const { get } = useAxiosGet<sway.ISwayLocale>("/sway_locales", {
        skipInitialRequest: true,
    });

    const getter = useCallback(
        (id?: number) => {
            if (id || params?.localeName) {
                get({ route: `/sway_locales/${id}?name=${params?.localeName}` })
                    .then((result) => {
                        if (result) {
                            dispatch(setSwayLocale(result as sway.ISwayLocale));
                            sessionSet(SWAY_STORAGE.Session.User.Locale, JSON.stringify(result));
                            window.location.reload()
                        }
                    })
                    .catch(console.error);
            }
        },
        [dispatch, get, params?.localeName],
    );

    return [useSelector(localeSelector) || initialSwayLocale, getter];
};
