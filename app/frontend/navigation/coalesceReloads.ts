import { router } from "@inertiajs/react";
import { HttpCancelledError, HttpNetworkError, type PendingVisit } from "@inertiajs/core";
import { logDev } from "app/frontend/sway_utils";

// @lat: [[system-shape#What a reader sees during the round trip#Transport failures need a handled exit]]
export const isTransportError = (error: unknown): boolean => {
    if (!error) return false;
    if (error instanceof HttpNetworkError) return true;
    if (error instanceof Error) {
        if (error.name === "HttpNetworkError") return true;
        if ("code" in error && (error as { code?: unknown }).code === "ERR_NETWORK") return true;
    }
    return false;
};

// @lat: [[system-shape#Keeping scores fresh#Two refreshes of one page collapse into one]]
export const COALESCE_WINDOW_MS = 2000;

const lastReloadStartedAt = new Map<string, number>();
const activeVisitKeys = new Map<string, string>();
interface PrefetchVisit extends PendingVisit {
    onPrefetchError?: (error: unknown) => void;
}
const activePrefetchVisits = new Map<string, PrefetchVisit>();

export const clearReloadCoalescing = (): void => {
    lastReloadStartedAt.clear();
    activeVisitKeys.clear();
    activePrefetchVisits.clear();
};

const pathWithQuery = (url: PendingVisit["url"]): string => {
    if (typeof url === "string") {
        const origin = typeof window === "undefined" ? "http://localhost" : window.location.origin;
        const parsed = new URL(url, origin);
        return `${parsed.pathname}${parsed.search}`;
    }
    return `${url?.pathname ?? ""}${url?.search ?? ""}`;
};

const displayedUrl = (): string =>
    typeof window === "undefined" ? "" : `${window.location.pathname}${window.location.search}`;

const isReadVisit = (visit: PendingVisit): boolean => String(visit.method ?? "get").toLowerCase() === "get";

export const getReloadKey = (visit: PendingVisit): string | null => {
    const only = visit.only;
    if (!only || only.length === 0) {
        return null;
    }
    const sortedProps = [...only].sort().join(",");
    return `${pathWithQuery(visit.url)}::${sortedProps}`;
};

const isDeferredPropsVisit = (visit: PendingVisit): boolean =>
    Boolean((visit as { deferredProps?: boolean }).deferredProps);

export const handleBeforeReload = (visit: PendingVisit, now: number = Date.now()): boolean => {
    // @lat: [[system-shape#Keeping scores fresh#Two refreshes of one page collapse into one]]
    if (!isReadVisit(visit)) {
        clearReloadCoalescing();
        return true;
    }

    if (visit.prefetch || isDeferredPropsVisit(visit)) {
        return true;
    }

    const key = getReloadKey(visit);
    if (!key) {
        lastReloadStartedAt.clear();
        return true;
    }

    if (pathWithQuery(visit.url) !== displayedUrl()) {
        return true;
    }

    const lastTime = lastReloadStartedAt.get(key);
    if (lastTime !== undefined && now - lastTime < COALESCE_WINDOW_MS) {
        logDev("coalesceReloads: suppressing duplicate reload for", key);
        return false;
    }

    lastReloadStartedAt.set(key, now);
    if (visit.id) {
        activeVisitKeys.set(visit.id, key);
    }
    return true;
};

export const handleReloadFailure = (visitId?: string): void => {
    if (!visitId) {
        clearReloadCoalescing();
        return;
    }
    const key = activeVisitKeys.get(visitId);
    if (key) {
        lastReloadStartedAt.delete(key);
        activeVisitKeys.delete(visitId);
    }
};

export const handleReloadFinish = (visitId?: string): void => {
    if (!visitId) return;
    activeVisitKeys.delete(visitId);
};

export const registerCoalesceReloads = (): (() => void) => {
    if (typeof window === "undefined") {
        return () => {};
    }

    const unBefore = router.on("before", (event) => {
        if (event.defaultPrevented) return;
        const allowed = handleBeforeReload(event.detail.visit);
        if (!allowed) {
            event.preventDefault();
            return false;
        }
    });

    const unPrefetching = router.on("prefetching", (event) => {
        const visit = event.detail.visit as PrefetchVisit;
        if (visit?.id) {
            activePrefetchVisits.set(visit.id, visit);
        }
    });

    const unFinish = router.on("finish", (event) => {
        const visitId = event.detail.visit?.id;
        handleReloadFinish(visitId);
        if (visitId) {
            activePrefetchVisits.delete(visitId);
        }
    });

    const unError = router.on("error", (event) => {
        handleReloadFailure(event.detail.visitId);
        if (event.detail.visitId) {
            activePrefetchVisits.delete(event.detail.visitId);
        }
    });

    const unNetworkError = router.on("networkError", (event) => {
        const error = event.detail?.error;

        if (activePrefetchVisits.size > 0) {
            const prefetchError = isTransportError(error) ? new HttpCancelledError() : error;
            for (const [, visit] of activePrefetchVisits.entries()) {
                const entry = router.getPrefetching(visit.url);
                if (entry?.response) {
                    entry.response.catch(() => {});
                }
                if (typeof visit.onPrefetchError === "function") {
                    visit.onPrefetchError(prefetchError);
                }
            }
            activePrefetchVisits.clear();
        }

        handleReloadFailure();

        if (isTransportError(error)) {
            event.preventDefault();
            return false;
        }
    });

    const unHttpException = router.on("httpException", () => {
        handleReloadFailure();
    });

    return () => {
        unBefore();
        unPrefetching();
        unFinish();
        unError();
        unNetworkError();
        unHttpException();
    };
};

if (typeof window !== "undefined") {
    registerCoalesceReloads();
}
