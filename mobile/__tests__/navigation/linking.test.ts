/**
 // @lat: [[mobile-navigation-test-guards#Why linking.test.ts checks the path pattern string instead of calling getStateFromPath]]
 */

import { linking } from "../../src/navigation/linking";

describe("linking config", () => {
    const profileScreens = (
        linking.config!.screens as Record<string, unknown> & {
            Profile: { screens: Record<string, string> };
        }
    ).Profile.screens;

    test("Profile.MembershipDetail is mapped to organizations/:orgId/memberships/:id", () => {
        expect(profileScreens.MembershipDetail).toBe("organizations/:orgId/memberships/:id");
    });

    test("Profile.MembershipsList is mapped to users/organization_memberships", () => {
        expect(profileScreens.MembershipsList).toBe("users/organization_memberships");
    });

    test("existing Profile route is preserved", () => {
        expect(profileScreens.ProfileHub).toBe("profile");
    });

    // @lat: [[well-known-controller-notes#Mobile: linking.ts#Why each path maps to one screen]]
    test("no path pattern maps to two screens", () => {
        const patterns: string[] = [];
        const collect = (screens: Record<string, unknown>): void => {
            for (const entry of Object.values(screens)) {
                if (typeof entry === "string") {
                    patterns.push(entry);
                    continue;
                }
                const {
                    path,
                    alias,
                    screens: nested,
                } = entry as {
                    path?: string;
                    alias?: string[];
                    screens?: Record<string, unknown>;
                };
                if (path !== undefined) patterns.push(path);
                patterns.push(...(alias ?? []));
                if (nested !== undefined) collect(nested);
            }
        };
        collect(linking.config!.screens as Record<string, unknown>);

        expect(patterns).not.toHaveLength(0);
        expect(patterns.filter((pattern, index) => patterns.indexOf(pattern) !== index)).toEqual([]);
    });

    test("prefixes include both sway.vote and app.sway.vote", () => {
        expect(linking.prefixes).toContain("https://sway.vote");
        expect(linking.prefixes).toContain("https://app.sway.vote");
    });

    /**
     // @lat: [[mobile-navigation-test-guards#Why linking.test.ts checks the path pattern string instead of calling getStateFromPath]]
     */
    test("MembershipDetail path pattern captures :orgId and :id segments", () => {
        const pattern = profileScreens.MembershipDetail;
        expect(pattern).toContain(":orgId");
        expect(pattern).toContain(":id");
        // The pattern must not be a fixed path with no placeholders.
        expect(pattern).toMatch(/organizations\/:orgId\/memberships\/:id/);
    });
});
