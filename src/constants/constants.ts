/** @format */

import { sway } from "sway";

import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "./notifications";

export const GOOGLE_STATIC_ASSETS_BUCKET = `https://firebasestorage.googleapis.com/v0/b/${process.env.REACT_APP_STORAGE_BUCKET}/o`;

export const PERMISSION_DENIED_ERROR_CODE = "permission-denied";

export const KEYCODE_ESC = "Escape";

export const SWAY_REDEEMING_INVITE_FROM_UID_COOKIE = "@sway/invitedBy";
export const SWAY_CACHING_OKAY_COOKIE = "@sway/firebase/caching";
export const SWAY_SESSION_LOCALE_KEY = "@sway/locale";
export const SWAY_USER_REGISTERED = "@sway/user";

export const GITHUB_LINK = "https://github.com/Plebeian-Technology/sway";
export const TWITTER_LINK = "https://twitter.com/Sway_Vote";

export const DEFAULT_ORGANIZATION: sway.IOrganization = {
    name: "Sway",
    iconPath: "sway.png",
    positions: {},
};

export const DEFAULT_USER_SETTINGS: sway.IUserSettings = {
    uid: "taco",
    hasCheckedSupportFab: false,
    messagingRegistrationToken: "",
    notificationFrequency: NOTIFICATION_FREQUENCY.Daily,
    notificationType: NOTIFICATION_TYPE.EmailSms,
    congratulations: {
        isCongratulateOnUserVote: true,
        isCongratulateOnInviteSent: true,
        isCongratulateOnSocialShare: true,
    },
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
    "economy",
];
if (CATEGORIES.length > 10) {
    throw new Error(
        `CATEGORIES constant list cannot exceed 10 items. Received ${CATEGORIES.length} items.`,
    );
}

export const INITIAL_SHARE_PLATFORMS = {
    email: 0,
    facebook: 0,
    telegram: 0,
    twitter: 0,
    whatsapp: 0,
};

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

export const CLOUD_FUNCTIONS = {
    createBillOfTheWeek: "createBillOfTheWeek",
    getUserSway: "getUserSway",
    getLegislatorUserScores: "getLegislatorUserScores",
    getUserLegislatorScore: "getUserLegislatorScore",
    sendUserInvites: "sendUserInvites",
    sendLegislatorEmail: "sendLegislatorEmail",
    sendLegislatorPhoneCall: "sendLegislatorPhoneCall",
    validateMailingAddress: "validateMailingAddress",
};

export const Collections: {
    Admins: "admins";
    BillsOfTheWeek: "bills";
    Bills: "bills";
    BillScores: "bill_scores";
    BillSummaries: "external_summaries";
    Legislators: "legislators";
    LegislatorVotes: "legislator_votes";
    Locales: "locales";
    Users: "users";
    UserSettings: "user_settings";
    UserInvites: "user_invites";
    UserBillShares: "user_bill_shares";
    UserVotes: "user_votes";
    Organizations: "organizations";
    OrganizationPositions: "positions";
    Notifications: "notifications";
    SwayVersion: "sway_version";
} = {
    Admins: "admins",
    BillsOfTheWeek: "bills",
    Bills: "bills",
    BillScores: "bill_scores",
    BillSummaries: "external_summaries",
    Legislators: "legislators",
    LegislatorVotes: "legislator_votes",
    Locales: "locales",
    Users: "users",
    UserSettings: "user_settings",
    UserInvites: "user_invites",
    UserBillShares: "user_bill_shares",
    UserVotes: "user_votes",
    Organizations: "organizations",
    OrganizationPositions: "positions",
    Notifications: "notifications",
    SwayVersion: "sway_version",
};

export const FIREBASE_PROJECT_ID: string | undefined =
    process.env.REACT_APP_PROJECT_ID;
export const FIREBASE_ORIGIN = `https://us-central1-${FIREBASE_PROJECT_ID}.cloudfunctions.net`;

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

export const ALERT_DELAY = 3000;

// eslint-disable-next-line
export enum EAuthProvider {
    Apple = "Apple",
    Google = "Google",
    Twitter = "Twitter",
}

// eslint-disable-next-line
export enum ESocial {
    Email = "email",
    Twitter = "twitter",
    Facebook = "facebook",
    WhatsApp = "whatsapp",
    Telegram = "telegram",
}

// eslint-disable-next-line
export enum ESwayLevel {
    Congress = "National",
    National = "National",
    Regional = "Regional",
    Local = "Local",
}

// eslint-disable-next-line
export enum ESwayLevelEnum {
    Congress,
    State,
    Local,
}

export const EXECUTIVE_BRANCH_TITLES = [
    "mayor",
    "governor",
    "president",
    "county executive",
    "manager",
    "city manager",
    "executive",
    "chief executive",
];

export const SHARE_PLATFORMS: {
    Email: sway.TSharePlatform;
    Facebook: sway.TSharePlatform;
    Telegram: sway.TSharePlatform;
    Twitter: sway.TSharePlatform;
    Whatsapp: sway.TSharePlatform;
} = {
    Email: "email",
    Facebook: "facebook",
    Telegram: "telegram",
    Twitter: "twitter",
    Whatsapp: "whatsapp",
};