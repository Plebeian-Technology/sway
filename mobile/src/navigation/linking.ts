import type { LinkingOptions } from "@react-navigation/native";
import type { RootParamList } from "./types";

// @lat: [[well-known-controller-notes#Mobile: linking.ts]]
export const linking: LinkingOptions<RootParamList> = {
    prefixes: ["https://sway.vote", "https://app.sway.vote", "sway://"],
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
                    BillDetail: { path: "bills/:id", parse: { id: Number } },
                },
            },
            Bills: {
                screens: {
                    BillsList: "bills",
                    PastBillsOfTheMonth: "past_bills_of_the_month",
                    BillDetail: { path: "bills/:id", parse: { id: Number } },
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
                    ProfileHub: "profile",
                    MembershipsList: "users/organization_memberships",
                    MembershipDetail: "organizations/:orgId/memberships/:id",
                },
            },
        },
    },
};
