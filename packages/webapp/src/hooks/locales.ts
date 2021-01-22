/** @format */

import { LOCALES } from "@sway/constants";
import { isEmptyObject } from "@sway/utils";
import { useState } from "react";
import { sway } from "sway";
import { useUserLocales } from "./users";

export const useLocale = (
    user: sway.IUser | undefined,
): [
    sway.IUserLocale | sway.ILocale,
    (userLocale: sway.IUserLocale | sway.ILocale) => void,
] => {
    const defaultLocale = !isEmptyObject(user?.locales) && user?.locales[0];

    return useState<sway.IUserLocale | sway.ILocale>(
        defaultLocale || LOCALES[0],
    );
};

export const useLocales = (): sway.IUserLocale[] => {
    return useUserLocales();
};
