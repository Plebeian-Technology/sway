// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { router } from "@inertiajs/react";
import type { PendingVisit } from "@inertiajs/core";
import {
    INTENTIONAL_EMPTY_LIST_PARAMETERS,
    isIntentionalEmptyListParameter,
} from "app/frontend/sway_utils/addressWithEmptyList";

export { INTENTIONAL_EMPTY_LIST_PARAMETERS, isIntentionalEmptyListParameter };

const cleanKey = (searchParams: URLSearchParams, name: string): void => {
    if (name.endsWith("[]")) {
        const base = name.slice(0, -2);
        searchParams.delete(base);
        searchParams.delete(name);
    } else {
        const bracket = `${name}[]`;
        searchParams.delete(name);
        searchParams.delete(bracket);
    }
    searchParams.set(name, "");
};

export function setQueryParamCleared(target: URLSearchParams, name: string): URLSearchParams;
export function setQueryParamCleared(target: URL, name: string): URL;
export function setQueryParamCleared(target: string, name: string): string;
export function setQueryParamCleared(
    target: URLSearchParams | URL | string,
    name: string,
): URLSearchParams | URL | string {
    if (target instanceof URLSearchParams) {
        cleanKey(target, name);
        return target;
    }

    if (target instanceof URL) {
        cleanKey(target.searchParams, name);
        return target;
    }

    const hashIdx = target.indexOf("#");
    const hasHash = hashIdx !== -1;
    const hash = hasHash ? target.slice(hashIdx) : "";
    const withoutHash = hasHash ? target.slice(0, hashIdx) : target;

    const queryIdx = withoutHash.indexOf("?");
    const beforeQuery = queryIdx !== -1 ? withoutHash.slice(0, queryIdx) : withoutHash;
    const queryString = queryIdx !== -1 ? withoutHash.slice(queryIdx + 1) : "";

    const searchParams = new URLSearchParams(queryString);
    cleanKey(searchParams, name);
    const qs = searchParams.toString();

    return `${beforeQuery}?${qs}${hash}`;
}

export function isQueryParamCleared(target: URLSearchParams | URL | string, name: string): boolean {
    if (isIntentionalEmptyListParameter(name)) {
        return false;
    }

    let searchParams: URLSearchParams;

    if (target instanceof URLSearchParams) {
        searchParams = target;
    } else if (target instanceof URL) {
        searchParams = target.searchParams;
    } else {
        const queryIdx = target.indexOf("?");
        if (queryIdx === -1) return false;
        const withoutHash = target.slice(queryIdx + 1).split("#")[0] ?? "";
        searchParams = new URLSearchParams(withoutHash);
    }

    if (searchParams.has(name)) {
        return searchParams.get(name) === "";
    }

    if (!name.endsWith("[]")) {
        const bracket = `${name}[]`;
        if (searchParams.has(bracket)) {
            return searchParams.get(bracket) === "";
        }
    } else {
        const base = name.slice(0, -2);
        if (searchParams.has(base)) {
            return searchParams.get(base) === "";
        }
    }

    return false;
}

const stripFromSearchParams = (params: URLSearchParams): void => {
    const entries = Array.from(params.entries());
    for (const [key] of entries) {
        params.delete(key);
    }
    for (const [key, value] of entries) {
        if (value !== "" || isIntentionalEmptyListParameter(key)) {
            params.append(key, value);
        }
    }
};

export function stripClearedQueryParams(target: URLSearchParams): URLSearchParams;
export function stripClearedQueryParams(target: URL): URL;
export function stripClearedQueryParams(target: string): string;
export function stripClearedQueryParams(target: URLSearchParams | URL | string): URLSearchParams | URL | string {
    if (target instanceof URLSearchParams) {
        stripFromSearchParams(target);
        return target;
    }

    if (target instanceof URL) {
        stripFromSearchParams(target.searchParams);
        return target;
    }

    if (!target.includes("?")) {
        return target;
    }

    const hashIdx = target.indexOf("#");
    const hasHash = hashIdx !== -1;
    const hash = hasHash ? target.slice(hashIdx) : "";
    const withoutHash = hasHash ? target.slice(0, hashIdx) : target;

    const queryIdx = withoutHash.indexOf("?");
    const beforeQuery = withoutHash.slice(0, queryIdx);
    const queryString = withoutHash.slice(queryIdx + 1);

    const searchParams = new URLSearchParams(queryString);
    stripFromSearchParams(searchParams);
    const qs = searchParams.toString();

    return `${beforeQuery}${qs ? `?${qs}` : ""}${hash}`;
}

export const stripClearedQueryParamsFromVisit = (visit: PendingVisit): void => {
    if (visit?.url) {
        stripClearedQueryParams(visit.url);
    }
};

let activeStripPointUnsubscribe: (() => void) | null = null;

export const registerClearedParamStripPoint = (): (() => void) => {
    if (typeof window === "undefined") {
        return () => {};
    }
    if (activeStripPointUnsubscribe) {
        return activeStripPointUnsubscribe;
    }
    if (typeof router?.on !== "function") {
        return () => {};
    }
    const unregister = router.on("before", (event) => {
        stripClearedQueryParamsFromVisit(event.detail.visit);
    });
    activeStripPointUnsubscribe = () => {
        unregister();
        activeStripPointUnsubscribe = null;
    };
    return activeStripPointUnsubscribe;
};

export const unregisterClearedParamStripPoint = (): void => {
    if (activeStripPointUnsubscribe) {
        activeStripPointUnsubscribe();
    }
};
