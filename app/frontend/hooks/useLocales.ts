/** @format */

import { router, usePage } from "@inertiajs/react";
import { useCallback, useMemo } from "react";
import { ISelectOption, sway } from "sway";
import { SWAY_STORAGE, logDev, sessionGet, toFormattedLocaleName } from "../sway_utils";

export const getDefaultSwayLocale = () => {
    const sessionLocale = sessionGet(SWAY_STORAGE.Session.User.Locale);
    if (sessionLocale) {
        return JSON.parse(sessionLocale);
    }
};

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

export const useLocales = () => {
    const swayLocales = usePage<sway.IPageProps>().props.swayLocales;
    const options = useMemo(() => swayLocales.map(toSelectOption), [swayLocales]);

    return { swayLocales, options };
};

export const useLocale = (): [sway.ISwayLocale, (localeId: number) => void] => {
    const swayLocale = usePage<sway.IPageProps>().props.swayLocale;
    logDev("useLocale - using swayLocale from props -", `${swayLocale.id} - ${swayLocale.name}`);

    const getLocale = useCallback((localeId: number) => {
        router.visit(`${window.location.origin}${window.location.pathname}?sway_locale_id=${localeId}`);
    }, []);

    return [swayLocale, getLocale];
};

export const useLocaleName = () => usePage<sway.IPageProps>().props.swayLocale?.name;
