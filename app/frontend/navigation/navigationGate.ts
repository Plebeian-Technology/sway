import type { PendingVisit } from "@inertiajs/core";

// @lat: [[navigation-placeholder-tracer#Why navigationGate.test.ts's mutation check defines a second predicate locally]]

const isPartial = (visit: PendingVisit): boolean => visit.only.length > 0 || visit.except.length > 0;

// @lat: [[navigation-placeholder-tracer#Why qualifiesForPlaceholder checks six fields]]
const withoutHash = (href: string): string => {
    const url = new URL(href);
    url.hash = "";
    return url.href;
};

// @lat: [[system-shape#What a reader sees during the round trip]]
export const qualifiesForPlaceholder = (visit: PendingVisit, currentHref: string): boolean =>
    !isPartial(visit) &&
    visit.prefetch === false &&
    visit.async === false &&
    visit.method === "get" &&
    visit.preserveState !== true &&
    withoutHash(visit.url.href) !== withoutHash(currentHref);

export const qualifiesForDim = (visit: PendingVisit, currentHref: string): boolean =>
    qualifiesForPlaceholder(visit, currentHref);
