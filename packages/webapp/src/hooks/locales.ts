/** @format */

import { LOCALES, SWAY_SESSION_LOCALE_KEY } from "@sway/constants";
import { isEmptyObject, IS_DEVELOPMENT } from "@sway/utils";
import { useState } from "react";
import { sway } from "sway";
import { useUserLocales } from "./users";

const getDefaultLocale = (user: sway.IUser | undefined) => {
    const _sessionLocale = sessionStorage.getItem(SWAY_SESSION_LOCALE_KEY);
    if (_sessionLocale) return JSON.parse(_sessionLocale);

    const _defaultLocale = !isEmptyObject(user?.locales) && user?.locales[0];
    return (
        _defaultLocale ||
        LOCALES[0]
    )
}

const setSwayLocaleSessionStorage = (locale: sway.IUserLocale | sway.ILocale) => {
    IS_DEVELOPMENT && console.log("Set locale in Sway session storage (dev)");
    sessionStorage.setItem(
        SWAY_SESSION_LOCALE_KEY,
        JSON.stringify(locale),
    );
}

export const useLocale = (
    user: sway.IUser | undefined,
    queryStringLocale?: sway.ILocale | null,
): [
    sway.IUserLocale | sway.ILocale,
    (userLocale: sway.IUserLocale | sway.ILocale) => void,
] => {
    const defaultLocale = queryStringLocale || getDefaultLocale(user);
    const [locale, setLocale] = useState<sway.IUserLocale | sway.ILocale>(defaultLocale);

    const handleSetLocale = (newLocale: sway.IUserLocale | sway.ILocale) => {
        setSwayLocaleSessionStorage(newLocale);
        setLocale(newLocale);
    }

    return [locale, handleSetLocale]
};

export const useLocales = (): sway.IUserLocale[] => {
    return useUserLocales();
};
