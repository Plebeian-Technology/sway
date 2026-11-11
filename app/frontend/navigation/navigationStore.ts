import { useSyncExternalStore } from "react";
import { router } from "@inertiajs/react";
import type { PendingVisit } from "@inertiajs/core";

import { qualifiesForDim, qualifiesForPlaceholder } from "app/frontend/navigation/navigationGate";
import { resolvePlaceholder, type TShapeKey } from "app/frontend/navigation/placeholderRegistry";

// @lat: [[navigation-placeholder-tracer#Why the store sets on before and clears on three attributed events]]

export interface INavigationState {
    placeholder: TShapeKey | null;
    pageName: string | null;
    dim: boolean;
}

export const NAVIGATION_IDLE: INavigationState = { placeholder: null, pageName: null, dim: false };

// @lat: [[navigation-placeholder-tracer#Why the treatment carries a watchdog timer]]
export const NAVIGATION_TREATMENT_MAX_MS = 60_000;

// @lat: [[navigation-placeholder-tracer#Why networkError and httpException shorten the bound instead of clearing]]
export const NAVIGATION_TREATMENT_UNATTRIBUTED_MS = 3_000;

let state: INavigationState = NAVIGATION_IDLE;
let activeVisitId: string | null = null;
let watchdog: ReturnType<typeof setTimeout> | undefined;
const listeners = new Set<() => void>();

const armWatchdog = (ms: number): void => {
    clearTimeout(watchdog);
    watchdog = setTimeout(() => {
        activeVisitId = null;
        setState(NAVIGATION_IDLE);
    }, ms);
};

const setState = (next: INavigationState): void => {
    state = next;
    clearTimeout(watchdog);
    watchdog = undefined;
    if (next !== NAVIGATION_IDLE) {
        armWatchdog(NAVIGATION_TREATMENT_MAX_MS);
    }
    listeners.forEach((listener) => listener());
};

export const navigationSnapshot = (): INavigationState => state;

export const subscribeNavigation = (listener: () => void): (() => void) => {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
};

export const useNavigationState = (): INavigationState =>
    useSyncExternalStore(subscribeNavigation, navigationSnapshot, navigationSnapshot);

// @lat: [[navigation-placeholder-tracer#Why the clear is keyed to the visit that raised the treatment]]
const clearFor = (visitId: string | null | undefined): void => {
    if (activeVisitId !== null && visitId !== activeVisitId) {
        return;
    }
    activeVisitId = null;
    setState(NAVIGATION_IDLE);
};

const handleBefore = (visit: PendingVisit): undefined => {
    const currentHref = window.location.href;
    const dim = qualifiesForDim(visit, currentHref);
    const placeholder = qualifiesForPlaceholder(visit, currentHref);

    if (!dim && !placeholder) {
        return undefined;
    }

    const entry = resolvePlaceholder(visit.url.pathname);
    activeVisitId = visit.id;
    setState({
        placeholder: placeholder ? entry.shape : null,
        pageName: placeholder ? entry.pageName : null,
        dim,
    });
    return undefined;
};

// @lat: [[navigation-placeholder-tracer#Why networkError and httpException shorten the bound instead of clearing]]
const shortenBound = (): void => {
    if (state === NAVIGATION_IDLE) return;
    armWatchdog(NAVIGATION_TREATMENT_UNATTRIBUTED_MS);
};

if (typeof window !== "undefined") {
    router.on("before", (event) => {
        if (event.defaultPrevented) return;
        return handleBefore(event.detail.visit);
    });
    router.on("finish", (event) => clearFor(event.detail.visit?.id));
    router.on("success", (event) => clearFor(event.detail.visitId));
    router.on("error", (event) => clearFor(event.detail.visitId));
    router.on("networkError", shortenBound);
    router.on("httpException", shortenBound);
}
