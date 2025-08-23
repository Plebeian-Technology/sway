/** @format */

import { router, usePage } from "@inertiajs/react";
import { useCallback, useMemo } from "react";
import { ISelectOption, sway } from "sway";
import { toFormattedLocaleName } from "../sway_utils";

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

export const useLocales = () => {
    const sway_locales = usePage<sway.IPageProps>().props.sway_locales;
    const options = useMemo(() => sway_locales.map(toSelectOption), [sway_locales]);

    return { sway_locales, options };
};

export const useLocale = (): [sway.ISwayLocale, (localeId: number) => void] => {
    const sway_locale = usePage<sway.IPageProps>().props.sway_locale;

    const getLocale = useCallback((localeId: number) => {
        router.visit(`${window.location.origin}${window.location.pathname}?sway_locale_id=${localeId}`);
    }, []);

    return [sway_locale, getLocale];
};

export const useLocaleName = () => usePage<sway.IPageProps>().props.sway_locale?.name;
