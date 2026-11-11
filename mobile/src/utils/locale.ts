// @lat: [[locale-name-is-derived#A locale's name is derived, not stored#Mobile locale formatting parity]]

export const CONGRESS_SWAY_LOCALE_NAME = "congress-congress-united_states";

export interface Locale {
    id: number;
    name: string;
    city: string;
    region_code: string;
    region_name: string;
    country: string;
    icon_url: string;
    time_zone: string;
    current_session_start_date: string;
    generic_portal_urls?: string[];
}

const titleizeChunk = (chunk: string): string => {
    if (!chunk) return "";
    return chunk
        .toLowerCase()
        .split("_")
        .filter(Boolean)
        .map((w) => w[0].toUpperCase() + w.slice(1))
        .join(" ");
};

export const isCongressLocale = (locale: Locale | string | undefined): boolean => {
    if (!locale) return false;
    return typeof locale === "string"
        ? locale === CONGRESS_SWAY_LOCALE_NAME
        : locale.name === CONGRESS_SWAY_LOCALE_NAME;
};

export const toFormattedLocaleName = (name: string | undefined, includeCountry = true): string => {
    if (!name) return "";
    if (isCongressLocale(name)) return "U.S. Congress";

    const chunks = name.split("-").map(titleizeChunk);
    const limited = includeCountry ? chunks : chunks.slice(0, 2);
    const unique = Array.from(new Set(limited));
    return unique.join(", ");
};
