/** @format */

import { LOCALES, SwayStorage } from "@sway/constants";
import { isCongressLocale, isEmptyObject, logDev } from "@sway/utils";
import { useState } from "react";
import { sway } from "sway";
import { localGet, localSet } from "../utils";
import { useHookedRepresentatives } from "./legislators";
import { useUserLocales } from "./users";

const getDefaultLocale = (user: sway.IUser | undefined) => {
    const stored = localGet(SwayStorage.Session.User.Locale);
    if (stored) {
        logDev("getDefaultLocale - return locale from local storage");
        return JSON.parse(stored);
    } else {
        logDev("getDefaultLocale - NO user locale found in local storage");
    }

    if (!user?.locales || isEmptyObject(user?.locales)) {
        logDev("getDefaultLocale - user has NO locales, return first locale from LOCALES constant");
        return LOCALES[0];
    } else if (user.locales.length > 1) {
        logDev("getDefaultLocale - user > 1 locales, return first, NON-CONRGESS, user locale");
        return user.locales.find((l) => !isCongressLocale(l));
    } else {
        logDev("getDefaultLocale - user has locales, return first user locale");
        return user.locales.first();
    }
};

const setSwayLocaleSessionStorage = (locale: sway.IUserLocale | sway.ILocale) => {
    logDev(`setSwayLocaleSessionStorage - Set locale - ${locale.name} - in local storage`);
    localSet(SwayStorage.Session.User.Locale, JSON.stringify(locale));
};

export const useLocale = (
    user: sway.IUser | undefined,
    queryStringLocale?: sway.ILocale | null,
): [sway.IUserLocale | sway.ILocale, (userLocale: sway.IUserLocale | sway.ILocale) => void] => {
    const defaultLocale = queryStringLocale || getDefaultLocale(user);
    logDev("useLocale - received default locale -", defaultLocale?.name);

    const [locale, setLocale] = useState<sway.IUserLocale | sway.ILocale>(defaultLocale);

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
