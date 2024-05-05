export const IS_DEVELOPMENT = window.location.hostname === "localhost"
export const IS_NOT_PRODUCTION = IS_DEVELOPMENT
export const IS_PRODUCTION = !IS_DEVELOPMENT

const userAgent = navigator.userAgent.toLowerCase();

export const LOAD_ERROR_MESSAGE = "Error loading Bill of the Week. Please navigate back to https://app.sway.vote.";

// TABLET DETECTION - https://stackoverflow.com/a/50195587/6410635
export const IS_TABLET =
    /(ipad|tablet|(android(?!.*mobile))|(windows(?!.*phone)(.*touch))|kindle|playbook|silk|(puffin(?!.*(IP|AP|WP))))/.test( // NOSONAR
        userAgent,
    );
export const IS_COMPUTER_WIDTH = window.innerWidth >= 960;

export const IS_MOBILE_PHONE: boolean = (() => {
    const toMatch = [
        /Android/i,
        /webOS/i,
        /iPhone/i,
        /iPad/i,
        /iPod/i,
        /BlackBerry/i,
        /Windows Phone/i,
    ];

    return toMatch.some((toMatchItem) => {
        return !!toMatchItem.exec(window.navigator.userAgent);
    });
})();

// BROWSER DETECTION - https://stackoverflow.com/a/26358856/6410635 - in use
const IS_FIREFOX = userAgent.indexOf("firefox") !== -1;
const IS_SAFARI = userAgent.indexOf("safari") !== -1;
const IS_CHROME = userAgent.indexOf("chrome") !== -1;

/** @format */

import { sway } from "sway";

import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "./notifications";

export const CONGRESS = 118;
// export const CONGRESS = 117;

export const KEYCODE_ESC = "Escape";

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
  throw new Error(`CATEGORIES constant list cannot exceed 10 items. Received ${CATEGORIES.length} items.`);
}

export const USER_LEGISLATOR = {
  MutuallyAbstained: 0,
  Agreed: 1,
  Disagreed: 2,
  NoLegislatorVote: null,
};

export const WEB_PUSH_NOTIFICATION_TOPICS = {
  billOfTheWeekWeb: "billOfTheWeekWeb",
};

export const CLOUD_FUNCTIONS = {
  createBillOfTheWeek: "createBillOfTheWeek",
  createUserLegislators: "createUserLegislators",
  getUserSway: "getUserSway",
  getLegislatorUserScores: "getLegislatorUserScores",
  getUserLegislatorScore: "getUserLegislatorScore",
  sendUserInvites: "sendUserInvites",
  sendLegislatorEmail: "sendLegislatorEmail",
  sendLegislatorPhoneCall: "sendLegislatorPhoneCall",
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

export const Support: {
  For: "FOR";
  for: "FOR";
  Yea: "FOR";
  yea: "FOR";
  Against: "AGAINST";
  Nay: "AGAINST";
  against: "AGAINST";
  nay: "AGAINST";
  Abstain: "ABSTAIN";
} = {
  For: "FOR",
  for: "FOR",
  Yea: "FOR",
  yea: "FOR",
  Against: "AGAINST",
  Nay: "AGAINST",
  against: "AGAINST",
  nay: "AGAINST",
  Abstain: "ABSTAIN",
};

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

export const INITIAL_SHARE_PLATFORMS = {
  email: 0,
  facebook: 0,
  telegram: 0,
  twitter: 0,
  whatsapp: 0,
};

// eslint-disable-next-line
export const ESharePlatforms = {
  Email: "email" as sway.TSharePlatform,
  Facebook: "facebook" as sway.TSharePlatform,
  Telegram: "telegram" as sway.TSharePlatform,
  Twitter: "twitter" as sway.TSharePlatform,
  Whatsapp: "whatsapp" as sway.TSharePlatform,
} as {
  Email: sway.TSharePlatform;
  Facebook: sway.TSharePlatform;
  Telegram: sway.TSharePlatform;
  Twitter: sway.TSharePlatform;
  Whatsapp: sway.TSharePlatform;
};

// eslint-disable-next-line
export enum ESwayLevel {
  Congress = "National",
  Regional = "Regional",
  Local = "Local",
}

export * from "./awards";
export * from "./dates";
export * from "./locales";
export * from "./notifications";
export * from "./routes";
export * from "./states";
export * from "./users";
