import { sway } from "sway";
import { default as _LOCALES } from "./locales.json";

export const LOCALES = _LOCALES as sway.ILocale[];

export const BALTIMORE_CITY_LOCALE_NAME = "baltimore-maryland-united_states";
export const BALTIMORE_COUNTY_LOCALE_NAME = "baltimore_county-maryland-united_states";
export const WASHINGTON_DC_LOCALE_NAME = "washington-district_of_columbia-united_states";
export const LOS_ANGELES_LOCALE_NAME = "los_angeles-california-united_states";
export const CONGRESS_LOCALE_NAME = "congress-congress-united_states";
export const CONGRESS_LOCALE = LOCALES.find((l) => l.name === CONGRESS_LOCALE_NAME) as sway.ILocale;

// eslint-disable-next-line
export enum ELocaleName {
    BALTIMORE = "baltimore-maryland-united_states",
    BALTIMORE_COUNTY = "baltimore_county-maryland-united_states",
    WASHINGTON_DC = "washington-district_of_columbia-united_states",
    LOS_ANGELES = "los_angeles-california-united_states",
    CONGRESS = "congress-congress-united_states",
}

export const LOCALE_GEOJSON_FEATURE_COUNCIL_DISTRICT_KEY: {
    [ELocaleName.BALTIMORE]: "COUNCIL_DI";
    [ELocaleName.BALTIMORE_COUNTY]: "";
    [ELocaleName.WASHINGTON_DC]: "";
    [ELocaleName.LOS_ANGELES]: "";
    [ELocaleName.CONGRESS]: "";
} = {
    [ELocaleName.BALTIMORE]: "COUNCIL_DI",
    [ELocaleName.BALTIMORE_COUNTY]: "",
    [ELocaleName.WASHINGTON_DC]: "",
    [ELocaleName.LOS_ANGELES]: "",
    [ELocaleName.CONGRESS]: "",
};

export const VOTING_WEBSITES_BY_LOCALE: {
    [ELocaleName.BALTIMORE]: "Baltimore Legistar";
    [ELocaleName.BALTIMORE_COUNTY]: "Baltimore County Website";
    [ELocaleName.LOS_ANGELES]: "LACityClerk Connect";
    [ELocaleName.WASHINGTON_DC]: "Washington DC LIMS";
    [ELocaleName.CONGRESS]: "congress.gov";
} = {
    [ELocaleName.BALTIMORE]: "Baltimore Legistar",
    [ELocaleName.BALTIMORE_COUNTY]: "Baltimore County Website",
    [ELocaleName.LOS_ANGELES]: "LACityClerk Connect",
    [ELocaleName.WASHINGTON_DC]: "Washington DC LIMS",
    [ELocaleName.CONGRESS]: "congress.gov",
};
