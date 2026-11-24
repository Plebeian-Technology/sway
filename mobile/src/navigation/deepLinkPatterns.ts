// @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
export const DEEP_LINK_PATTERNS = [
    "/bills/*",
    "/bills",
    "/past_bills_of_the_month",
    "/legislators/*",
    "/legislators",
    "/bill_of_the_month",
    "/bill_of_the_week",
    "/organizations/*/memberships/*",
    "/organizations/*",
    "/organizations",
    "/s/*",
    "/invite/*/*",
    "/invites/*/*",
    "/bill_shares/*",
];

// @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
export const androidPathData = (pattern: string): Record<string, string> => {
    const withoutTrailingStar = pattern.endsWith("*") ? pattern.slice(0, -1) : null;
    if (withoutTrailingStar !== null && !withoutTrailingStar.includes("*")) {
        return { pathPrefix: withoutTrailingStar };
    }
    if (pattern.includes("*")) {
        return { pathPattern: pattern.replaceAll("*", ".*") };
    }
    return { path: pattern };
};
