import { createSelector } from "@reduxjs/toolkit";
import { CONGRESS_LOCALE } from "@sway/constants";
import { isCongressLocale, getUserLocaleFromLocales } from "@sway/utils";
import { useSelector } from "react-redux";
import { sway } from "sway";

const userState = (state: sway.IAppState) => {
    return state.user;
};

const localeState = (state: sway.IAppState) => {
    return state.locale || CONGRESS_LOCALE;
};

const userLocaleSelector = createSelector([userState, localeState], (user, locale) =>
    getUserLocaleFromLocales(user.user, locale),
);
const userLocaleNameSelector = createSelector(
    [userState, localeState],
    (user, locale) => getUserLocaleFromLocales(user.user, locale)?.name || "",
);
const userLocaleDistrictSelector = createSelector(
    [userState, localeState],
    (user, locale) => getUserLocaleFromLocales(user.user, locale)?.district || "",
);
const userLocaleRegionCodeSelector = createSelector([userState, localeState], (user, locale) =>
    (
        getUserLocaleFromLocales(user.user, locale)?.regionCode ||
        user.user?.regionCode ||
        ""
    ).toUpperCase(),
);
const userLocaleIsCongressSelector = createSelector([userState, localeState], (user, locale) =>
    isCongressLocale(getUserLocaleFromLocales(user.user, locale)),
);

export const useUserLocale = (): sway.IUserLocale | undefined => {
    return useSelector(userLocaleSelector);
};
export const useUserLocaleName = (): string | undefined => {
    return useSelector(userLocaleNameSelector);
};
export const useUserLocaleDistrict = (): string => {
    return useSelector(userLocaleDistrictSelector);
};
export const useUserLocaleRegionCode = (): string => {
    return useSelector(userLocaleRegionCodeSelector);
};
export const useIsCongressUserLocale = (): boolean => {
    return useSelector(userLocaleIsCongressSelector);
};
