import { router, usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { notify } from "app/frontend/sway_utils";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";
import { sway } from "sway";

// @lat: [[locale-name-is-derived#SwayLocale naming conventions across the frontend and mobile]]

export const useSwayLocales = () => {
    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    const { sway_locales, sway_locale_options } = usePage<sway.IPageProps>().props;

    return { sway_locales: sway_locales ?? [], options: sway_locale_options ?? [] };
};

// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
export const useAdminSwayLocaleOptions = () => usePage<sway.IPageProps>().props.admin_sway_locale_options ?? [];

export interface ISwayLocaleSwitchHandlers {
    onError?: () => void;
}

export const useSwayLocale = (
    refreshProps?: string[],
): [
    sway.ISwayLocale | undefined,
    (swayLocaleId: number, handlers?: ISwayLocaleSwitchHandlers) => void,
    number | undefined,
] => {
    const sway_locale = usePage<sway.IPageProps>().props.sway_locale;

    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
    const [pendingSwayLocaleId, setPendingSwayLocaleId] = useState<number | undefined>(undefined);

    const getSwayLocale = useCallback(
        (swayLocaleId: number, handlers?: ISwayLocaleSwitchHandlers) => {
            // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
            const params = new URLSearchParams(window.location.search);

            // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
            if (params.has("page")) {
                setQueryParamCleared(params, "page");
            }
            if (params.has("bills_page")) {
                setQueryParamCleared(params, "bills_page");
            }
            if (params.has("bills_legislative_session_id")) {
                setQueryParamCleared(params, "bills_legislative_session_id");
            }
            if (params.has("legislative_session_id")) {
                setQueryParamCleared(params, "legislative_session_id");
            }

            params.set("sway_locale_id", String(swayLocaleId));

            // @lat: [[hover-prefetch-links#Why jurisdiction switching flushes the prefetch cache]]
            router.flushAll?.();
            router.get(
                `${window.location.pathname}?${params.toString()}`,
                {},
                {
                    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
                    only: refreshProps,
                    preserveState: Boolean(refreshProps),
                    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
                    replace: true,
                    onStart: () => setPendingSwayLocaleId(swayLocaleId),
                    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
                    onFinish: () => {
                        setPendingSwayLocaleId(undefined);
                    },
                    // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
                    onError: () => {
                        notify({ level: "error", title: "Could not switch locale." });
                        // @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]
                        handlers?.onError?.();
                    },
                },
            );
        },
        [refreshProps],
    );

    return [sway_locale, getSwayLocale, pendingSwayLocaleId];
};

export const useSwayLocaleSlug = () => usePage<sway.IPageProps>().props.sway_locale?.name;
