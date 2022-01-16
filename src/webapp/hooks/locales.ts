/** @format */

import { LOCALES, SWAY_SESSION_LOCALE_KEY } from "src/constants";
import { isEmptyObject, logDev } from "src/utils";
import { useState } from "react";
import { sway } from "sway";
import { useHookedRepresentatives } from "./legislators";
import { useUserLocales } from "./users";

const getDefaultLocale = (user: sway.IUser | undefined) => {
    const _sessionLocale = sessionStorage.getItem(SWAY_SESSION_LOCALE_KEY);
    if (_sessionLocale) return JSON.parse(_sessionLocale);

    const _defaultLocale = !isEmptyObject(user?.locales) && user?.locales[0];
    return _defaultLocale || LOCALES[0];
};

const setSwayLocaleSessionStorage = (
    locale: sway.IUserLocale | sway.ILocale,
) => {
    logDev("Set locale in Sway session storage");
    sessionStorage.setItem(SWAY_SESSION_LOCALE_KEY, JSON.stringify(locale));
};

export const useLocale = (
    user: sway.IUser | undefined,
    queryStringLocale?: sway.ILocale | null,
): [
    sway.IUserLocale | sway.ILocale,
    (userLocale: sway.IUserLocale | sway.ILocale) => void,
] => {
    const defaultLocale = queryStringLocale || getDefaultLocale(user);
    const [locale, setLocale] = useState<sway.IUserLocale | sway.ILocale>(
        defaultLocale,
    );

    const handleSetLocale = (newLocale: sway.IUserLocale | sway.ILocale) => {
        setSwayLocaleSessionStorage(newLocale);
        setLocale(newLocale);
    };

    return [locale, handleSetLocale];
};

export const useLocales = (): sway.IUserLocale[] => {
    return useUserLocales();
};

export const getDefaultLocaleLegislators = async (
    user: sway.IUser,
    locale: sway.ILocale,
): Promise<sway.ILegislator[]> => {
    const [, getReps] = useHookedRepresentatives();

    const reps = await getReps(
        user,
        {
            ...locale,
            district: `${user.regionCode}0`,
        },
        true,
    );

    return reps?.representatives || [];
};
