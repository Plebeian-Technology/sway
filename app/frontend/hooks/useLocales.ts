/** @format */

import { createSelector } from "@reduxjs/toolkit";
import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { useCallback, useEffect, useMemo } from "react";
import { useDispatch, useSelector } from "react-redux";
import { ISelectOption, sway } from "sway";
import { setSwayLocale, setSwayLocales } from "../redux/actions/localeActions";
import { SWAY_STORAGE, sessionGet, sessionSet, toFormattedLocaleName } from "../sway_utils";

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

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

export const useLocaleName = () => useSelector(localeNameSelector);

export const useLocales = () => {
    const dispatch = useDispatch();
    const { get, isLoading } = useAxiosGet<sway.ISwayLocale[]>("/sway_locales", { skipInitialRequest: true });
    const locales = useSelector(localesSelector);
    const options = useMemo(() => locales.map(toSelectOption), [locales]);

    useEffect(() => {
        get()
            .then((items) => {
                if (items) {
                    dispatch(setSwayLocales(items as sway.ISwayLocale[]));
                }
            })
            .catch(console.error);
    }, [dispatch, get]);

    return { locales, options, isLoading };
};

export const useLocale = (): [sway.ISwayLocale, (id?: number) => Promise<void>] => {
    const dispatch = useDispatch();

    const params = new URLSearchParams(window.location.search) as {
        localeName?: string;
    };

    const { get } = useAxiosGet<sway.ISwayLocale>("/sway_locales", {
        skipInitialRequest: true,
    });

    const getter = useCallback(
        async (id?: number) => {
            if (id || params?.localeName) {
                const paramsName = params.localeName ? `name=${params?.localeName}` : "";
                return get({ route: `/sway_locales/${id}?${paramsName}` })
                    .then((result) => {
                        if (result) {
                            dispatch(setSwayLocale(result as sway.ISwayLocale));
                            sessionSet(SWAY_STORAGE.Session.User.Locale, JSON.stringify(result));
                            // window.location.reload();
                        }
                    })
                    .catch(console.error);
            }
        },
        [dispatch, get, params?.localeName],
    );

    return [useSelector(localeSelector), getter];
};
