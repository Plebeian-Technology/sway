import { sway } from "sway";
import { titleize } from ".";
import { uniq } from "lodash";
import { CONGRESS_SWAY_LOCALE_NAME } from "app/frontend/sway_constants";

const fromLocaleNameItem = (string: string | undefined): string => {
    if (string === "") return "";
    if (!string) {
        console.error("fromLocaleNameItem received falsey item string. Returning blank string in place.");
        return "";
    }

    return titleize(string.split("_").join(" "));
};

const splitLocaleName = (name: string): string[] => {
    if (!name) return [];
    return name.split("-");
};

export const toFormattedLocaleName = (name: string, includeCountry = true): string => {
    if (isCongressLocale(name)) {
        return "U.S. Congress";
    }
    if (!includeCountry) {
        return uniq(
            splitLocaleName(name)
                .map(fromLocaleNameItem)
                .filter((_, i: number) => i < 2),
        ).join(", ");
    }
    return uniq(splitLocaleName(name).map(fromLocaleNameItem)).join(", ");
};

export const isCongressLocale = (swayLocale: sway.ISwayLocale | string | undefined): boolean => {
    if (!swayLocale) return false;

    if (typeof swayLocale === "string") {
        return swayLocale === CONGRESS_SWAY_LOCALE_NAME;
    }
    return swayLocale.name === CONGRESS_SWAY_LOCALE_NAME;
};

// @lat: [[locale-name-is-derived#A locale's name is derived, not stored#Why localeLabelFor takes a fallback slug]]
export const localeLabelFor = (
    locales: sway.ISwayLocale[],
    swayLocaleId: number,
    fallbackSlug?: string | null,
): string | undefined => {
    const match = locales.find((swayLocale) => swayLocale.id === swayLocaleId);
    if (match) return toFormattedLocaleName(match.name, false);
    return fallbackSlug ? toFormattedLocaleName(fallbackSlug, false) : undefined;
};
