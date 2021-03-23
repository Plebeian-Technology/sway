import { sway } from "sway";
import * as _LOCALES from "./locales.json";

export const LOCALES = _LOCALES;

export const BALTIMORE_CITY_LOCALE_NAME = "baltimore-maryland-united_states";
export const BALTIMORE_COUNTY_LOCALE_NAME = "baltimore_county-maryland-united_states";
export const WASHINGTON_DC_LOCALE_NAME =
    "washington-district_of_columbia-united_states";
export const LOS_ANGELES_LOCALE_NAME = "los_angeles-california-united_states";
export const CONGRESS_LOCALE_NAME = "congress-congress-united_states";
export const CONGRESS_LOCALE = LOCALES.find(
    (l) => l.name === CONGRESS_LOCALE_NAME,
) as sway.ILocale;

export const VOTING_WEBSITES_BY_LOCALE: {
    [BALTIMORE_CITY_LOCALE_NAME]: "Baltimore Legistar";
    [BALTIMORE_COUNTY_LOCALE_NAME]: "Baltimore County Website";
    [LOS_ANGELES_LOCALE_NAME]: "LACityClerk Connect";
    [WASHINGTON_DC_LOCALE_NAME]: "Washington DC LIMS";
    [CONGRESS_LOCALE_NAME]: "congress.gov";
} = {
    [BALTIMORE_CITY_LOCALE_NAME]: "Baltimore Legistar",
    [BALTIMORE_COUNTY_LOCALE_NAME]: "Baltimore County Website",
    [LOS_ANGELES_LOCALE_NAME]: "LACityClerk Connect",
    [WASHINGTON_DC_LOCALE_NAME]: "Washington DC LIMS",
    [CONGRESS_LOCALE_NAME]: "congress.gov",
};
