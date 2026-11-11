// @lat: [[hover-prefetch-links#Links that warm before the click]]
export const PREFETCH_CACHE_FOR: [string, string] = ["30s", "5m"];

// @lat: [[query-parameter-navigation-carry#Excluded route constants and security boundaries]]
export const NAVIGATION_EXCLUDED_ROUTE_PREFIXES = [
    "/api/v1",
    "/api",
    "/sessions",
    "/test/sessions",
    "/passkeys",
    "/registrations",
    "/phone_verification",
    "/sway_registration",
    "/users/webauthn",
    "/users/passkeys",
] as const;

export type NavigationExcludedRoutePrefix = (typeof NAVIGATION_EXCLUDED_ROUTE_PREFIXES)[number];

export const normalizeNavigationPathname = (pathOrUrl: string): string => {
    if (!pathOrUrl || typeof pathOrUrl !== "string") {
        return "";
    }
    const withoutHash = pathOrUrl.split("#")[0] ?? "";
    const withoutQuery = withoutHash.split("?")[0] ?? "";
    let pathname = withoutQuery.trim();

    if (pathname.includes("://")) {
        try {
            pathname = new URL(pathname).pathname;
        } catch {
            const slashIdx = pathname.indexOf("/", pathname.indexOf("://") + 3);
            pathname = slashIdx !== -1 ? pathname.slice(slashIdx) : "/";
        }
    }

    if (pathname && !pathname.startsWith("/")) {
        pathname = `/${pathname}`;
    }

    if (pathname.length > 1 && pathname.endsWith("/")) {
        pathname = pathname.replace(/\/+$/, "");
    }

    return pathname;
};

export const isNavigationExcludedRoute = (pathOrUrl: string): boolean => {
    const pathname = normalizeNavigationPathname(pathOrUrl);
    if (!pathname) return false;

    return NAVIGATION_EXCLUDED_ROUTE_PREFIXES.some((prefix) => {
        const normalizedPrefix = prefix.endsWith("/") && prefix.length > 1 ? prefix.replace(/\/+$/, "") : prefix;
        return pathname === normalizedPrefix || pathname.startsWith(`${normalizedPrefix}/`);
    });
};
