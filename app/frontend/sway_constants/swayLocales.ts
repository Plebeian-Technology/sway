// @lat: [[locale-name-is-derived#A locale's name is derived, not stored#Frontend SwayLocale constants]]
export const CONGRESS_SWAY_LOCALE_NAME = "congress-congress-united_states";

export enum ESwayLocaleName {
    BALTIMORE = "baltimore-maryland-united_states",
    BALTIMORE_COUNTY = "baltimore_county-maryland-united_states",
    WASHINGTON_DC = "washington-district_of_columbia-united_states",
    LOS_ANGELES = "los_angeles-california-united_states",
    MARYLAND = "maryland-maryland-united_states",
    CONGRESS = "congress-congress-united_states",
}

export const VOTING_WEBSITES_BY_SWAY_LOCALE = {
    [ESwayLocaleName.BALTIMORE]: "Baltimore Legistar",
    [ESwayLocaleName.BALTIMORE_COUNTY]: "Baltimore County Website",
    [ESwayLocaleName.LOS_ANGELES]: "LACityClerk Connect",
    [ESwayLocaleName.WASHINGTON_DC]: "Washington DC LIMS",
    [ESwayLocaleName.MARYLAND]: "mgaleg.maryland.gov",
    [ESwayLocaleName.CONGRESS]: "congress.gov",
} as const;
