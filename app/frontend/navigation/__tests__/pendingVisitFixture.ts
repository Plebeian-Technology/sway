import type { PendingVisit } from "@inertiajs/core";

// @lat: [[navigation-placeholder-tracer#Why pendingVisitFixture copies the router's own defaults object]]

// No cast: the compiler is the drift trip wire when @inertiajs/core adds a Visit field.
const BASE: PendingVisit = {
    method: "get",
    data: {},
    replace: false,
    preserveScroll: false,
    preserveState: false,
    only: [],
    except: [],
    headers: {},
    errorBag: "",
    forceFormData: false,
    queryStringArrayFormat: "brackets",
    async: false,
    showProgress: true,
    prefetch: false,
    fresh: false,
    reset: [],
    preserveUrl: false,
    preserveErrors: false,
    invalidateCacheTags: [],
    viewTransition: false,
    component: null,
    pageProps: null,
    cached: false,
    id: "fixture-visit",
    url: new URL("https://sway.test/"),
    completed: false,
    cancelled: false,
    interrupted: false,
};

export const pendingVisitFixture = (overrides: Partial<PendingVisit> = {}): PendingVisit => ({
    ...BASE,
    ...overrides,
});
