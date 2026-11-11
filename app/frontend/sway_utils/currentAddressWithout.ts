// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

export const currentAddressWithout = (owned: string[]): string => {
    const url = new URL(window.location.href);
    owned.forEach((name) => {
        const bracket = name.endsWith("[]") ? name : `${name}[]`;
        const base = name.endsWith("[]") ? name.slice(0, -2) : name;
        if (url.searchParams.has(base) || url.searchParams.has(bracket)) {
            setQueryParamCleared(url.searchParams, name);
        }
    });
    return `${url.pathname}${url.search}`;
};
