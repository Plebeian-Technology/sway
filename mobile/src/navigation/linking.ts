import { getStateFromPath, type LinkingOptions } from "@react-navigation/native";
import { discardPendingDeepLink, subscribeToLinks } from "./pendingDeepLink";
import type { RootParamList } from "./types";
import { inviteAttribution } from "../state/inviteAttribution";

const LINK_SAFE = /^[A-Za-z0-9_-]+$/;

// @lat: [[well-known-controller-notes#Mobile: linking.ts#Invite links store a key and open no screen]]
const inviteAttributionKeyFor = (path: string): string | null => {
    const [kind, ...rest] = path.split(/[?#]/)[0].split("/").filter(Boolean);
    const value = rest[rest.length - 1] ?? "";
    if (!LINK_SAFE.test(value)) return null;

    if (kind === "s" && rest.length === 1) return `s:${value}`;
    if ((kind === "invite" || kind === "invites") && rest.length === 2) return `invite:${value}`;
    return null;
};

// @lat: [[well-known-controller-notes#Mobile: linking.ts]]
export const linking: LinkingOptions<RootParamList> = {
    prefixes: ["https://sway.vote", "https://app.sway.vote", "sway://"],
    subscribe: subscribeToLinks,
    // @lat: [[well-known-controller-notes#Mobile: linking.ts#Invite links store a key and open no screen]]
    getStateFromPath(path, options) {
        const inviteKey = inviteAttributionKeyFor(path);
        if (inviteKey === null) return getStateFromPath(path, options);

        inviteAttribution.set(inviteKey);
        discardPendingDeepLink();
        return undefined;
    },
    config: {
        screens: {
            Auth: "sign-in",
            Feed: {
                screens: {
                    FeedList: "feed",
                },
            },
            Home: {
                screens: {
                    BillOfTheMonth: { path: "bill_of_the_month", alias: ["bill_of_the_week"] },
                },
            },
            Bills: {
                screens: {
                    BillsList: "bills",
                    PastBillsOfTheMonth: "past_bills_of_the_month",
                    BillDetail: { path: "bills/:id", parse: { id: Number } },
                    BillShare: "bill_shares/:shareUuid",
                },
            },
            Legislators: {
                screens: {
                    LegislatorsList: "legislators",
                    LegislatorDetail: "legislators/:id",
                },
            },
            Orgs: {
                screens: {
                    OrgsList: "organizations",
                    OrgDetail: "organizations/:id",
                },
            },
            Profile: {
                screens: {
                    // @lat: [[naming-decisions#Naming decisions#A route name is not a label]]
                    ProfileHub: { path: "profile", alias: ["users/profile"] },
                    MembershipsList: "users/organization_memberships",
                    MembershipDetail: "organizations/:orgId/memberships/:id",
                    MembershipInviteConfirm: {
                        path: "organizations/:orgId/membership_invites/:token/confirm_accept",
                        parse: { orgId: Number },
                    },
                },
            },
        },
    },
};
