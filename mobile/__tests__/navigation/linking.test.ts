import { getStateFromPath } from "@react-navigation/native";

import { linking } from "../../src/navigation/linking";
import { inviteAttribution } from "../../src/state/inviteAttribution";

describe("linking config", () => {
    const profileScreens = (
        linking.config!.screens as Record<string, unknown> & {
            Profile: { screens: Record<string, string> };
        }
    ).Profile.screens;

    // @lat: [[mobile-navigation-test-guards#How linking.test.ts checks where a path lands]]
    test("Profile.MembershipDetail is mapped to organizations/:orgId/memberships/:id", () => {
        expect(profileScreens.MembershipDetail).toBe("organizations/:orgId/memberships/:id");
    });

    test("Profile.MembershipsList is mapped to users/organization_memberships", () => {
        expect(profileScreens.MembershipsList).toBe("users/organization_memberships");
    });

    test("ProfileHub answers the web profile path", () => {
        const focusedRoute = (path: string) =>
            linking.getStateFromPath!(path, linking.config as never)?.routes[0].state?.routes[0].name;

        expect(focusedRoute("profile")).toBe("ProfileHub");
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

    test("MembershipDetail path pattern captures :orgId and :id segments", () => {
        const pattern = profileScreens.MembershipDetail;
        expect(pattern).toContain(":orgId");
        expect(pattern).toContain(":id");
        // The pattern must not be a fixed path with no placeholders.
        expect(pattern).toMatch(/organizations\/:orgId\/memberships\/:id/);
    });
});

// @lat: [[well-known-controller-notes#Mobile: linking.ts#Invite links store a key and open no screen]]
describe("invite links", () => {
    const INVITE_UUID = "0b9f6c2e-1d4a-4c8e-9f3b-2a7d5e6c1f00";
    const stateFor = (path: string) => linking.getStateFromPath!(path, linking.config as never);

    beforeEach(() => {
        inviteAttribution.clear();
    });

    it("stores the short key of an s/<key> link and opens no screen", () => {
        expect(stateFor("s/abc-123_x")).toBeUndefined();
        expect(inviteAttribution.get()).toBe("s:abc-123_x");
    });

    it.each(["invite", "invites"])("stores the invite uuid of an %s/<user id>/<uuid> link", (prefix) => {
        expect(stateFor(`/${prefix}/42/${INVITE_UUID}?utm=1`)).toBeUndefined();
        expect(inviteAttribution.get()).toBe(`invite:${INVITE_UUID}`);
    });

    it("replaces an older key with a newer one", () => {
        stateFor("s/first");
        stateFor("s/second");

        expect(inviteAttribution.get()).toBe("s:second");
    });

    it.each(["s/abc%2F..", "s/a:b", "invite/42/not%20safe", "s", "invite/42"])("stores nothing for %s", (path) => {
        stateFor(path);

        expect(inviteAttribution.get()).toBeNull();
    });

    it("leaves every other path to React Navigation", () => {
        expect(stateFor("bills/12")).toEqual(getStateFromPath("bills/12", linking.config as never));
        expect(stateFor("bills/12")).toBeDefined();
        expect(inviteAttribution.get()).toBeNull();
    });
});

// @lat: [[well-known-controller-notes#Mobile: linking.ts#A bill share link opens the shared bill]]
describe("bill share links", () => {
    it("resolve to the share screen in the Bills section with the share uuid", () => {
        const shareUuid = "550e8400-e29b-41d4-a716-446655440000";

        const state = linking.getStateFromPath!(`bill_shares/${shareUuid}`, linking.config as never);

        expect(state?.routes[0]).toEqual(
            expect.objectContaining({
                name: "Bills",
                state: expect.objectContaining({
                    routes: [expect.objectContaining({ name: "BillShare", params: { shareUuid } })],
                }),
            }),
        );
    });
});

// @lat: [[membership-invite-accept-flow#Mobile: MembershipInviteConfirmScreen, the confirm step for an emailed link]]
describe("membership invite email links", () => {
    const profileRoute = (path: string) => {
        const state = linking.getStateFromPath!(path, linking.config as never);
        return state?.routes[0].state?.routes[0];
    };

    it("resolve to the confirm screen with a numeric orgId and the token unchanged", () => {
        const token = "signed-token--abc123";

        expect(profileRoute(`organizations/5/membership_invites/${token}/confirm_accept`)).toEqual(
            expect.objectContaining({ name: "MembershipInviteConfirm", params: { orgId: 5, token } }),
        );
    });

    it("leave an organization link on the organization's detail screen", () => {
        expect(profileRoute("organizations/5")).toEqual(expect.objectContaining({ name: "OrgDetail" }));
    });
});
