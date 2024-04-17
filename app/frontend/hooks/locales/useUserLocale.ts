import { createSelector } from "@reduxjs/toolkit";
import { CONGRESS_LOCALE } from "app/frontend/sway_constants";
import { getUserLocaleFromLocales, isCongressLocale, isEmptyObject, logDev } from "app/frontend/sway_utils";
import { useSelector } from "react-redux";
import { sway } from "sway";
import { sessionGet, SWAY_STORAGE } from "../../sway_utils";

const userState = (state: sway.IAppState) => {
    return state.user;
};

const getDefaultLocale = () => {
    const sessionLocale = sessionGet(SWAY_STORAGE.Session.User.Locale);
    if (sessionLocale) {
        return JSON.parse(sessionLocale);
    } else {
        return CONGRESS_LOCALE;
    }
};

const localeState = (state: sway.IAppState) => {
    return !state.locale || isEmptyObject(state.locale) ? getDefaultLocale() : state.locale;
};

const userLocaleSelector = createSelector([userState, localeState], (user, locale) =>
    getUserLocaleFromLocales(user.user, locale),
);
const userLocaleNameSelector = createSelector(
    [userState, localeState],
    (user, locale) => getUserLocaleFromLocales(user.user, locale)?.name || "",
);
const userLocaleDistrictSelector = createSelector([userState, localeState], (user, locale) => {
    logDev("userLocaleDistrictSelector", { user: user.user, localeState, locale });
    return getUserLocaleFromLocales(user.user, locale)?.district || "";
});
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
