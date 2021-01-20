import { CONGRESS_LOCALE_NAME } from "@sway/constants";
import { sway } from "sway";
import { titleize } from ".";

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
    return `${toLocaleNameItem(city)}-${toLocaleNameItem(
        region,
    )}-${toLocaleNameItem(country)}`;
};

export const toFormattedLocaleName = (name: string): string => {
    if (name === CONGRESS_LOCALE_NAME) {
        return "United States Congress"
    }
    return splitLocaleName(name).map(fromLocaleNameItem).join(", ");
};

export const toUserLocale = (l: sway.ILocale | string): sway.IUserLocale => {
    if (typeof l === "string") {
        return { name: l } as sway.IUserLocale;
    }
    return { name: l.name } as sway.IUserLocale;
};
export const toLocale = (l: sway.IUserLocale | string): sway.ILocale => {
    if (typeof l === "string") {
        return { name: l } as sway.ILocale;
    }
    return { name: l.name } as sway.ILocale;
};
