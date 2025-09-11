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

    users: {
        organization_memberships: "/users/organization_memberships",
    },

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
