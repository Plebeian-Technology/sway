
import { sway } from "sway";
import { titleize } from ".";
import { isEmpty } from "lodash";
import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";

export const SELECT_LOCALE_LABEL = "Select Locale";
export const LOCALE_NOT_LISTED_LABEL = "I don't see my Locale listed.";

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

export const splitLocaleName = (name: string): string[] => {
    if (!name) return [];
    return name.split("-");
};

export const fromLocaleName = (name: string) => {
    if (!name) {
        return {
            city: "",
            region: "",
            country: "",
        };
    }

    const [city, region, country] = splitLocaleName(name);
    return {
        city,
        region,
        country,
    };
};

export const toLocaleName = (address: sway.IAddress) => {
    return `${toLocaleNameItem(address.city)}-${toLocaleNameItem(address.regionCode)}-${toLocaleNameItem(address.country)}`;
};

export const toFormattedLocaleName = (name: string, includeCountry = true): string => {
    if (!includeCountry) {
        return splitLocaleName(name)
            .map(fromLocaleNameItem)
            .filter((_, i: number) => i < 2)
            .join(", ");
    }
    return splitLocaleName(name).map(fromLocaleNameItem).join(", ");
};

export const findNotCongressLocale = (locales: sway.ISwayLocale[]): sway.ISwayLocale => {
    return locales.find((l) => l.name !== CONGRESS_LOCALE_NAME) as sway.ISwayLocale;
};

export const isCongressLocale = (locale: sway.ISwayLocale | string | undefined): boolean => {
    if (!locale) return false;

    if (typeof locale === "string") {
        return locale === CONGRESS_LOCALE_NAME;
    }
    return locale.name === CONGRESS_LOCALE_NAME;
};

export const isNotUsersLocale = (user: sway.IUser | undefined, locale: sway.ISwayLocale): boolean => {
    if (!user) return false;

    const localeNames_ = user?.locales.map((l) => l.name);
    if (!localeNames_) return true;

    return locale.name !== CONGRESS_LOCALE_NAME && !localeNames_.includes(locale.name);
};

const getLocaleByEquality = (
    locale: sway.ISwayLocale | string | undefined,
    l: sway.ISwayLocale,
) => {
    if (!locale) return false;

    if (typeof locale === "string") {
        return l.name === locale;
    } else {
        return l.name === locale.name;
    }
};

export const getUserLocaleFromLocales = (
    user: sway.IUser,
    locale: sway.ISwayLocale | string,
): sway.ISwayLocale | undefined => {
    return (user?.locales || []).find((l: sway.ISwayLocale) =>
        getLocaleByEquality(typeof locale === "string" ? locale : locale?.name, l),
    );
};

export const localeNames = (user: sway.IUser | undefined): string[] => {
    if (!user) return [];

    return user.locales.map((l) => l.name);
};

export const getUserLocales = (user: sway.IUser | undefined) => {
    if (!user?.locales || isEmpty(user?.locales)) {
        return [];
    }
    return user.locales;
};
