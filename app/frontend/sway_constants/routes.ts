import { KeyOf } from "sway";

export const ROUTES = {
    index: "/",
    signin: "/signin",
    sign_up: "/sign_up",
    // logout: "/logout",
    logout: "/users/webauthn/sessions/0",
    registration: "sway_registration",
    invite: "/invite",

    notifications: "/notifications",

    // Drawer
    influence: "/influence",
    userOrganizationMemberships: "/user_organization_memberships",
    userSettings: "/settings",

    legislators: "/legislators",
    legislator: (localeName = ":localeName", external_legislator_id = ":external_legislator_id") =>
        `/legislators/${localeName}/${external_legislator_id}`,

    billOfTheWeek: "/bill_of_the_week",
    pastBills: "/bills",
    bill: (bill_id: string | number = ":bill_id") => `/bills/${bill_id}`,

    billOfTheWeekCreator: "/bills/new",
    billOfTheWeekCreatorEdit: (bill_id: string | number = ":bill_id") => `/bills/${bill_id}/edit`,

    geocoder: "/geocoder",
};

export type RouteKey = KeyOf<typeof ROUTES>;
