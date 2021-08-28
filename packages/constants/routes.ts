export const ROUTES = {
    index: "/",
    influence: "/influence",
    signin: "/signin",
    signup: "/signup",
    logout: "/logout",
    passwordreset: "/passwordreset",
    registrationIntroduction: "/registration/introduction",
    registration: "/registration",
    registrationV2: "/registrationV2",
    userSettings: "/settings",
    legislators: "/legislators",
    legislator: (
        localeName = ":localeName",
        externalLegislatorId = ":externalLegislatorId",
    ) => `/legislator/${localeName}/${externalLegislatorId}`,
    billOfTheWeek: "/bill-of-the-week",
    bill: (localeName = ":localeName", billFirestoreId = ":billFirestoreId") =>
        `/bill/${localeName}/${billFirestoreId}`,
    pastBills: "/past-bills-of-the-week",
    invite: "/invite/:uid",
};
