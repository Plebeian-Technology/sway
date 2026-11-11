// @lat: [[query-parameter-navigation-carry#Centralized interception mechanism]]
// @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { router as coreRouter, type PendingVisit } from "@inertiajs/core";
import * as InertiaReact from "@inertiajs/react";
import { isNavigationExcludedRoute } from "app/frontend/sway_constants/navigation";

const getRouter = () => {
    try {
        if (Object.keys(InertiaReact).includes("router")) {
            const r = (InertiaReact as Record<string, unknown>)["router"];
            if (r && typeof (r as { on?: unknown }).on === "function") {
                return r as typeof coreRouter;
            }
        }
    } catch {
        // Fall back to @inertiajs/core
    }
    return coreRouter;
};
import {
    getAllowedCarryParametersForPath,
    getFeatureForPath,
    getParameterFamily,
} from "app/frontend/sway_constants/queryParameters";
import {
    isIntentionalEmptyListParameter,
    isQueryParamCleared,
    stripClearedQueryParamsFromVisit,
} from "app/frontend/sway_utils/queryParamClearedSignal";

export interface NavigationCarryOptions {
    allowedParameters?: readonly string[] | Set<string>;
    currentUrl?: URL | string;
}

const resolveCurrentUrl = (options?: NavigationCarryOptions, origin: string = "http://localhost"): URL | null => {
    if (options?.currentUrl) {
        return options.currentUrl instanceof URL ? options.currentUrl : new URL(options.currentUrl, origin);
    }
    if (typeof window !== "undefined" && window.location?.href) {
        return new URL(window.location.href);
    }
    return null;
};

export function applyNavigationCarryToVisit(visit: PendingVisit, options?: NavigationCarryOptions): void {
    if (!visit?.url) return;

    const origin = typeof window !== "undefined" ? window.location.origin : "http://localhost";
    const destinationUrl = visit.url instanceof URL ? visit.url : new URL(visit.url, origin);

    if (isNavigationExcludedRoute(destinationUrl.pathname)) {
        stripClearedQueryParamsFromVisit(visit);
        return;
    }

    const currentUrl = resolveCurrentUrl(options, origin);

    if (!currentUrl || !currentUrl.search) {
        stripClearedQueryParamsFromVisit(visit);
        return;
    }

    const currentParams = currentUrl.searchParams;
    const destFeature = getFeatureForPath(destinationUrl.pathname);
    const sourceFeature = currentUrl ? getFeatureForPath(currentUrl.pathname) : null;
    const isGet = !visit.method || String(visit.method).toLowerCase() === "get";

    let allowed: Set<string>;
    if (options?.allowedParameters) {
        allowed = new Set(Array.from(options.allowedParameters).map((p) => p.replace(/\[\]$/, "")));
    } else {
        allowed = getAllowedCarryParametersForPath(
            destinationUrl.pathname,
            currentUrl ? currentUrl.pathname : null,
            isGet,
        );
    }

    const activeFeature =
        sourceFeature && destFeature && sourceFeature === destFeature
            ? destFeature
            : !isGet && sourceFeature
              ? sourceFeature
              : destFeature;

    const visitedKeys = new Set<string>();

    for (const [rawKey] of currentParams.entries()) {
        if (visitedKeys.has(rawKey)) continue;
        visitedKeys.add(rawKey);

        const baseKey = rawKey.replace(/\[\]$/, "");

        if (!allowed.has(baseKey) && !allowed.has(rawKey)) {
            continue;
        }

        if (isQueryParamCleared(currentParams, rawKey) || isQueryParamCleared(currentParams, baseKey)) {
            continue;
        }

        const family = getParameterFamily(baseKey, activeFeature);

        const destHasParam =
            destinationUrl.searchParams.has(rawKey) ||
            family.some((k) => destinationUrl.searchParams.has(k) || destinationUrl.searchParams.has(`${k}[]`));

        if (destHasParam) {
            continue;
        }

        let dataHasParam = false;
        if (visit.data) {
            if (typeof FormData !== "undefined" && visit.data instanceof FormData) {
                const formData = visit.data;
                dataHasParam = formData.has(rawKey) || family.some((k) => formData.has(k) || formData.has(`${k}[]`));
            } else if (typeof visit.data === "object" && visit.data !== null) {
                const dataObj = visit.data;
                dataHasParam =
                    Object.prototype.hasOwnProperty.call(dataObj, rawKey) ||
                    family.some(
                        (k) =>
                            Object.prototype.hasOwnProperty.call(dataObj, k) ||
                            Object.prototype.hasOwnProperty.call(dataObj, `${k}[]`),
                    );
            }
        }

        if (dataHasParam) {
            continue;
        }

        // @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
        if (Array.isArray(visit.only) && visit.only.includes("selected_stages") && family.includes("selected_stages")) {
            continue;
        }

        const values = currentParams.getAll(rawKey);
        for (const val of values) {
            if (val !== "" || isIntentionalEmptyListParameter(rawKey)) {
                destinationUrl.searchParams.append(rawKey, val);
            }
        }
    }

    if (typeof visit.url === "string") {
        visit.url = destinationUrl;
    }

    stripClearedQueryParamsFromVisit(visit);
}

export function isCarriedSelfPrefetch(visit: PendingVisit, options?: NavigationCarryOptions): boolean {
    if (!visit?.prefetch || !visit?.url) return false;

    const origin = typeof window !== "undefined" ? window.location.origin : "http://localhost";
    const currentUrl = resolveCurrentUrl(options, origin);
    if (!currentUrl) return false;

    const destinationUrl = visit.url instanceof URL ? visit.url : new URL(visit.url, currentUrl.origin);
    const sameOrigin = destinationUrl.origin === currentUrl.origin || destinationUrl.origin === origin;
    return sameOrigin && destinationUrl.pathname === currentUrl.pathname && destinationUrl.search === currentUrl.search;
}

let activeCarryUnsubscribe: (() => void) | null = null;

export const registerQueryParamNavigationCarry = (options?: NavigationCarryOptions): (() => void) => {
    if (typeof window === "undefined") {
        return () => {};
    }
    if (activeCarryUnsubscribe) {
        if (!options) {
            return activeCarryUnsubscribe;
        }
        activeCarryUnsubscribe();
    }
    const currentRouter = getRouter();
    if (typeof currentRouter?.on !== "function") {
        return () => {};
    }
    const unregister = currentRouter.on("before", (event) => {
        const visit = event.detail.visit;
        applyNavigationCarryToVisit(visit, options);
        if (isCarriedSelfPrefetch(visit, options)) {
            event.preventDefault();
            return false;
        }
    });
    activeCarryUnsubscribe = () => {
        unregister();
        activeCarryUnsubscribe = null;
    };
    return activeCarryUnsubscribe;
};

export const unregisterQueryParamNavigationCarry = (): void => {
    if (activeCarryUnsubscribe) {
        activeCarryUnsubscribe();
    }
};

export const isNavigationCarryRegistered = (): boolean => activeCarryUnsubscribe !== null;

if (typeof window !== "undefined") {
    registerQueryParamNavigationCarry();
}
