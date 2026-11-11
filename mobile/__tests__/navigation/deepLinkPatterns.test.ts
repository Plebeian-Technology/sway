import { DEEP_LINK_PATTERNS, androidPathData } from "../../src/navigation/deepLinkPatterns";
import { linking } from "../../src/navigation/linking";

// @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
describe("androidPathData", () => {
    it("uses a prefix when the trailing star is the only one", () => {
        expect(androidPathData("/bills/*")).toEqual({ pathPrefix: "/bills/" });
    });

    // @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
    it("drops only the star, so Android claims nothing iOS leaves alone", () => {
        for (const pattern of DEEP_LINK_PATTERNS) {
            const { pathPrefix } = androidPathData(pattern);
            if (pathPrefix === undefined) continue;

            expect(`${pathPrefix}*`).toBe(pattern);
        }
    });

    it("uses an exact path when there is no star", () => {
        expect(androidPathData("/bill_of_the_month")).toEqual({ path: "/bill_of_the_month" });
        expect(androidPathData("/bill_of_the_week")).toEqual({ path: "/bill_of_the_week" });
    });

    it("includes both /bill_of_the_month and /bill_of_the_week in DEEP_LINK_PATTERNS", () => {
        expect(DEEP_LINK_PATTERNS).toContain("/bill_of_the_month");
        expect(DEEP_LINK_PATTERNS).toContain("/bill_of_the_week");
    });

    it("uses a pattern when a star sits in the middle", () => {
        expect(androidPathData("/organizations/*/memberships/*")).toEqual({
            pathPattern: "/organizations/.*/memberships/.*",
        });
    });

    // @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
    it("never hands Android a prefix containing a star", () => {
        for (const pattern of DEEP_LINK_PATTERNS) {
            const data = androidPathData(pattern);
            expect(data.pathPrefix ?? "").not.toContain("*");
        }
    });

    // Every pattern must translate to exactly one of Android's three keys.
    it("translates every declared pattern to one Android rule", () => {
        expect(DEEP_LINK_PATTERNS.length).toBeGreaterThan(0);
        for (const pattern of DEEP_LINK_PATTERNS) {
            expect(Object.keys(androidPathData(pattern))).toHaveLength(1);
        }
    });
});

// @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
describe("every claimed address has a screen that answers it", () => {
    const routePaths = (): string[] => {
        const found: string[] = [];
        const walk = (node: unknown): void => {
            if (typeof node !== "object" || node === null) return;
            const record = node as Record<string, unknown>;
            const screens = (record.screens ?? record) as Record<string, unknown>;
            for (const value of Object.values(screens)) {
                if (typeof value === "string") {
                    found.push(value);
                } else {
                    walk(value);
                }
            }
        };
        walk(linking.config);
        return found;
    };

    // @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
    const answers = (pattern: string, route: string): boolean => {
        const claimed = pattern.replace(/^\//, "").split("/");
        const served = route.split("/");
        if (claimed.length !== served.length) return false;

        return claimed.every((segment, index) => {
            const other = served[index];
            if (segment === "*") return other.startsWith(":");
            return segment === other;
        });
    };

    // @lat: [[well-known-controller-notes#Mobile: deepLinkPatterns.ts]]
    it("finds a screen for each one", () => {
        const paths = routePaths();
        expect(paths).not.toHaveLength(0);

        const unanswered = DEEP_LINK_PATTERNS.filter((pattern) => !paths.some((route) => answers(pattern, route)));

        expect(unanswered).toEqual([]);
    });
});
