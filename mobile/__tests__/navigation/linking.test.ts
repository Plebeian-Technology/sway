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
