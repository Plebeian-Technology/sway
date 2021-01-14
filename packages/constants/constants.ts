/** @format */

import { sway } from "sway";
import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "./notifications";

export const CURRENT_COUNCIL_START_DATE = new Date("December 10, 2020");

export const GOOGLE_STATIC_ASSETS_BUCKET =
    process.env.NODE_ENV === "development"
        ? "https://firebasestorage.googleapis.com/v0/b/sway-dev-3187f.appspot.com/o"
        : "https://firebasestorage.googleapis.com/v0/b/sway-7947e.appspot.com/o";

export const KEYCODE_ESC = "Escape";

export const SWAY_CACHING_OKAY_COOKIE = "@sway/caching:enabled";

export const LOCAL_STORAGE_LOCALE_KEY = "@sway/locale";

export const DEFAULT_LOCALE_NAME = "baltimore-maryland-united_states";

export const DEFAULT_ORGANIZATION: sway.IOrganization = {
    name: "Sway",
    iconPath: "sway.png",
    positions: {},
}

export const DEFAULT_USER_LOCALE: sway.IUserLocale = {
    name: DEFAULT_LOCALE_NAME,
    district: Math.floor(Math.random() * Math.floor(14)) + 1,
    isSwayConfirmed: false,
    isRegisteredToVote: false,
} as sway.IUserLocale;

export const DEFAULT_USER_SETTINGS: sway.IUserSettings = {
    uid: "taco",
    hasCheckedSupportFab: false,
    messagingRegistrationToken: "",
    notificationFrequency: NOTIFICATION_FREQUENCY.Daily,
    notificationType: NOTIFICATION_TYPE.Email,
};

// NOTE: Because firebase .where(`in`) has a limit of 10 items
// This list of Categories cannot exceed 10
export const CATEGORIES = [
    "health",
    "housing",
    "infrastructure",
    "police",
    "political reform",
    "transportation",
];
if (CATEGORIES.length > 10) {
    throw new Error(
        `CATEGORIES constant list cannot exceed 10 items. Received ${CATEGORIES.length} items.`,
    );
}

export const USER_LEGISLATOR: {
    MutuallyAbstained: 0;
    Agreed: 1;
    Disagreed: 2;
    NoLegislatorVote: null;
} = {
    MutuallyAbstained: 0,
    Agreed: 1,
    Disagreed: 2,
    NoLegislatorVote: null,
};

export const WEB_PUSH_NOTIFICATION_TOPICS: {
    billOfTheWeekWeb: "billOfTheWeekWeb";
} = {
    billOfTheWeekWeb: "billOfTheWeekWeb",
};

export const CLOUD_FUNCTIONS: {
    createBillOfTheWeek: "createBillOfTheWeek";
    aggregateUserScores: "aggregateUserScores";
    validateMailingAddress: "validateMailingAddress";
} = {
    createBillOfTheWeek: "createBillOfTheWeek",
    aggregateUserScores: "aggregateUserScores",
    validateMailingAddress: "validateMailingAddress",
};

export const Collections: {
    BillsOfTheWeek: "bills";
    Bills: "bills";
    BillScores: "bill_scores";
    BillSummaries: "external_summaries";
    Legislators: "legislators";
    LegislatorVotes: "legislator_votes";
    Locales: "locales";
    UserVotes: "user_votes";
    UserLegislatorScores: "user_legislator_scores";
    Districts: "district";
    UserLegislatorVotes: "user_legislator_votes";
    Users: "users";
    UserSettings: "user_settings";
    UserInvites: "user_invites";
    Admins: "admins";
    Organizations: "organizations";
    OrganizationPositions: "positions";
} = {
    BillsOfTheWeek: "bills",
    Bills: "bills",
    BillScores: "bill_scores",
    BillSummaries: "external_summaries",
    Legislators: "legislators",
    LegislatorVotes: "legislator_votes",
    Locales: "locales",
    UserVotes: "user_votes",
    UserLegislatorScores: "user_legislator_scores",
    Districts: "district",
    UserLegislatorVotes: "user_legislator_votes",
    Users: "users",
    UserSettings: "user_settings",
    UserInvites: "user_invites",
    Admins: "admins",
    Organizations: "organizations",
    OrganizationPositions: "positions",
};

export const FIREBASE_PROJECT_ID: string | undefined =
    process.env.NODE_ENV === "development"
        ? process.env.REACT_APP_DEV_PROJECT_ID
        : process.env.REACT_APP_PROJECT_ID;
export const FIREBASE_ORIGIN: string = `https://us-central1-${FIREBASE_PROJECT_ID}.cloudfunctions.net`;

export const Support: {
    For: "for";
    for: "for";
    Yea: "for";
    yea: "for";
    Against: "against";
    Nay: "against";
    against: "against";
    nay: "against";
    Abstain: "abstain";
} = {
    For: "for",
    for: "for",
    Yea: "for",
    yea: "for",
    Against: "against",
    Nay: "against",
    against: "against",
    nay: "against",
    Abstain: "abstain",
};

export const ALERT_DELAY: number = 3000;

export const VOTING_WEBSITES_BY_LOCALE: {
    "washington-district_of_columbia-united_states": "Washington DC LIMS",
    "baltimore-maryland-united_states": "Baltimore Legistar",
} = {
    "washington-district_of_columbia-united_states": "Washington DC LIMS",
    "baltimore-maryland-united_states": "Baltimore Legistar",
}