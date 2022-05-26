import { CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import { sway } from "sway";
import { titleize } from ".";
import { isEmptyObject } from "./utils";

export const LOCALES_WITHOUT_CONGRESS = LOCALES.filter((l) => l.name !== CONGRESS_LOCALE_NAME);

export const SELECT_LOCALE_LABEL = "Select Locale";
export const LOCALE_NOT_LISTED_LABEL = "I don't see my Locale listed.";

export const isAtLargeLocale = (locale: sway.IUserLocale) => {
    return locale.district === `${locale.regionCode.toUpperCase()}0`;
};

export const toLocaleNameItem = (string: string | undefined): string => {
    if (!string) {
        console.error(
            "toLocaleNameItem received falsey item string. Returning blank string in place.",
        );
        return "";
    }

    return string
        .toLowerCase()
        .split(/[^A-Za-z]/)
        .join("_");
};

export const fromLocaleNameItem = (string: string | undefined): string => {
    if (string === "") return "";
    if (!string) {
        console.error(
            "fromLocaleNameItem received falsey item string. Returning blank string in place.",
        );
        return "";
    }

    return titleize(string.split("_").join(" "));
};

export const splitLocaleName = (name: string) => {
    return name.split("-");
};

export const fromLocaleName = (name: string) => {
    const [city, region, country] = splitLocaleName(name);
    return {
        city,
        region,
        country,
    };
};

export const toLocaleName = (city: string, region: string, country: string) => {
    return `${toLocaleNameItem(city)}-${toLocaleNameItem(region)}-${toLocaleNameItem(country)}`;
};

export const toFormattedLocaleName = (name: string, includeCountry = true): string => {
    if (name === CONGRESS_LOCALE_NAME) {
        return "United States Congress";
    }
    if (!includeCountry) {
        return splitLocaleName(name)
            .map(fromLocaleNameItem)
            .filter((_, i: number) => i < 2)
            .join(", ");
    }
    return splitLocaleName(name).map(fromLocaleNameItem).join(", ");
};

export const findNotCongressLocale = (locales: sway.IUserLocale[]): sway.IUserLocale => {
    return locales.find((l) => l.name !== CONGRESS_LOCALE_NAME) as sway.IUserLocale;
};

export const isCongressLocale = (locale: sway.ILocale | string): boolean => {
    if (typeof locale === "string") {
        return locale === CONGRESS_LOCALE_NAME;
    }
    return locale.name === CONGRESS_LOCALE_NAME;
};

export const isNotUsersLocale = (user: sway.IUser | undefined, locale: sway.ILocale): boolean => {
    if (!user) return false;

    const userLocaleNames_ = user?.locales && user?.locales.map((l) => l.name);
    if (!userLocaleNames_) return true;

    return locale.name !== CONGRESS_LOCALE_NAME && !userLocaleNames_.includes(locale.name);
};

const getLocaleByEquality = (locale: sway.ILocale | string, l: sway.ILocale | sway.IUserLocale) => {
    if (typeof locale === "string") {
        return l.name === locale;
    } else {
        return l.name === locale.name;
    }
};

export const userLocaleFromLocales = (
    user: sway.IUser,
    locale: sway.ILocale | string,
): sway.IUserLocale | undefined => {
    if (!user.locales) {
        return LOCALES.find((l) => getLocaleByEquality(locale, l)) as sway.IUserLocale | undefined;
    }

    return user.locales.find((l: sway.IUserLocale) => getLocaleByEquality(locale, l));
};

export const userLocaleNames = (user: sway.IUser | undefined): string[] => {
    if (!user) return [];

    return user.locales.map((l) => l.name);
};

export const getUserLocales = (user: sway.IUser | undefined) => {
    if (!user?.locales || isEmptyObject(user?.locales)) {
        return LOCALES;
    }
    return user.locales;
};

export const findLocale = (localeName: string): sway.ILocale | undefined => {
    if (!localeName) return;
    return LOCALES.find((locale) => locale.name === localeName);
};

export const toLocale = (l: sway.IUserLocale | string): sway.ILocale => {
    if (typeof l === "string") {
        return findLocale(l) as sway.ILocale;
    }
    return findLocale(l.name) as sway.ILocale;
};

export const toUserLocale = (l: sway.ILocale | string): sway.IUserLocale => {
    if (typeof l === "string") {
        return findLocale(l) as sway.IUserLocale;
    }
    return l as sway.IUserLocale;
};
