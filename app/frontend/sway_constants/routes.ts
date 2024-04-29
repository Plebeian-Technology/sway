export const ROUTES = {
    index: "/",
    signin: "/signin",
    sign_up: "/sign_up",
    logout: "/logout",
    registration: "sway_registration",
    invite: "/invite/:uid",

    // Drawer
    influence: "/influence",
    userSettings: "/settings",

    legislators: "/legislators",
    legislator: (localeName = ":localeName", externalLegislatorId = ":externalLegislatorId") =>
        `/legislators/${localeName}/${externalLegislatorId}`,

    billOfTheWeek: "/bill-of-the-week",
    pastBills: "/bills",
    bill: (localeName = ":localeName", billFirestoreId = ":billFirestoreId") =>
        `/bills/${localeName}/${billFirestoreId}`,

    billOfTheWeekCreator: "/admin/bills/creator",
};
