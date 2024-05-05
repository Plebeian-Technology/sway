export const ROUTES = {
    index: "/",
    signin: "/signin",
    sign_up: "/sign_up",
    // logout: "/logout",
    logout: "/users/webauthn/sessions/0",
    registration: "sway_registration",
    invite: "/invite/:uid",

    // Drawer
    influence: "/influence",
    userSettings: "/settings",

    legislators: "/legislators",
    legislator: (localeName = ":localeName", externalLegislatorId = ":externalLegislatorId") =>
        `/legislators/${localeName}/${externalLegislatorId}`,

    billOfTheWeek: "/bill_of_the_week",
    pastBills: "/bills",
    bill: (billId: string | number = ":billId") =>
        `/bills/${billId}`,

    billOfTheWeekCreator: "/admin/bills/creator",
};
