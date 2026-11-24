import { KeyOf } from "sway";

export const ROUTES = {
    index: "/",
    signin: "/",
    sign_up: "/sign_up",
    logout: "/users/webauthn/sessions/0",
    registration: "sway_registration",
    invite: "/invite",

    notifications: "/notifications",
    feed: "/feed",

    influence: "/influence",

    // @lat: [[public-organizations-endpoint#The public organizations endpoint]]
    publicOrganizations: "/public/organizations",
    publicOrganization: (organizationId: string | number = ":id") => `/public/organizations/${organizationId}`,

    organizationFollows: "/organization_follows",
    organizationFollow: (id: string | number = ":id") => `/organization_follows/${id}`,
    organizationFollowPreferences: (id: string | number = ":id") => `/organization_follows/${id}/preferences`,

    notificationsOrgDefaults: "/notifications/org_defaults",

    organizations: {
        memberships: {
            index: (organizationId: string | number) => `/organizations/${organizationId}/memberships`,
            show: (organizationId: string | number, membershipId: string | number) =>
                `/organizations/${organizationId}/memberships/${membershipId}`,
            new: (organizationId: string | number) => `/organizations/${organizationId}/memberships/new`,
            update: (organizationId: string | number, membershipId: string | number) =>
                `/organizations/${organizationId}/memberships/${membershipId}`,
            destroy: (organizationId: string | number, membershipId: string | number) =>
                `/organizations/${organizationId}/memberships/${membershipId}`,
            leave: (organizationId: string | number) => `/organizations/${organizationId}/memberships/leave`,
        },
        positions: {
            index: (organizationId: string | number) => `/organizations/${organizationId}/positions`,
            new: (organizationId: string | number) => `/organizations/${organizationId}/positions/new`,
            create: (organizationId: string | number) => `/organizations/${organizationId}/positions`,
            update: (organizationId: string | number, positionId: string | number) =>
                `/organizations/${organizationId}/positions/${positionId}`,
            destroy: (organizationId: string | number, positionId: string | number) =>
                `/organizations/${organizationId}/positions/${positionId}`,
        },
    },

    profile: "/profile",
    apiKeys: "/api_keys",

    user: (id: string | number) => `/users/${id}`,

    users: {
        organization_memberships: "/users/organization_memberships",
        passkeys: "/users/passkeys",
        editAddress: "/users/address/edit",
        signOutAllDevices: "/users/sign_out_all_devices",
    },

    userSettings: "/settings",

    legislators: "/legislators",
    // @lat: [[legislators-controller-design#Why the frontend legislator route helper accepts two argument shapes]]
    legislator: (idOrLocale: string | number = ":id", id?: string | number) => `/legislators/${id ?? idOrLocale}`,

    billOfTheMonth: "/bill_of_the_month",
    bills: "/bills",
    pastBills: "/bills",
    pastBillsOfTheMonth: "/past_bills_of_the_month",
    bill: (bill_id: string | number = ":bill_id") => `/bills/${bill_id}`,
    billSummaryReports: (bill_id: string | number = ":bill_id") => `/bills/${bill_id}/summary_reports`,
    userBillShares: "/user_bill_shares",

    // @lat: [[bill-creator-tab-url-routing#The frontend ROUTES constant (app/frontend/sway_constants/routes.ts)]]
    billCreator: "/admin/bill_creator/new",
    billCreatorTab: (
        bill_id: string | number = ":bill_id",
        tab: "creator" | "schedule" | "pipeline" | "summary" | "positions" = "creator",
    ) => `/admin/bill_creator/${bill_id}/${tab}`,

    // @lat: [[bill-creator-tab-url-routing#The frontend ROUTES constant (app/frontend/sway_constants/routes.ts)]]
    admin: "/admin",
    admin_llm_settings: "/admin/llm_settings",
    admin_categories: "/admin/categories",
    admin_bill_summary_reports: "/admin/bill_summary_reports",
    admin_registration_funnel: "/admin/registration_funnel",
    // @lat: [[news-article-evidence#Article identity and bill association]]
    admin_bill_news_articles: (bill_id: string | number) => `/admin/bills/${bill_id}/news_articles`,
    admin_bill_news_article: (bill_id: string | number, id: string | number) =>
        `/admin/bills/${bill_id}/news_articles/${id}`,
    reassignmentDismiss: (id: number | string = ":id") => `/reassignment_notifications/${id}/dismiss`,
    dismissReassignmentNotification: (id: number | string = ":id") => `/reassignment_notifications/${id}/dismiss`,
};

export type RouteKey = KeyOf<typeof ROUTES>;
