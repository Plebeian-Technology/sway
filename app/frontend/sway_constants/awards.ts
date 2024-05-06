
import { sway } from "sway";

export const AWARD_TYPES: {
    Vote: sway.awards.TAwardType;
    BillShare: sway.awards.TAwardType;
    Invite: sway.awards.TAwardType;
    Sway: sway.awards.TAwardType;
} = {
    Vote: "Vote",
    BillShare: "BillShare",
    Invite: "Invite",
    Sway: "Sway",
};

export const AWARD_ICONS_BY_TYPE: sway.awards.TAwardByType = {
    Vote: {
        tooltip: (count: number, city: string): string => `Voted on ${count} bills in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Vote on ${nextCount} bills in ${city}.`,
        icons: {
            blue: "ballotbox-blue",
            red: "ballotbox-red",
            black: "ballotbox-black",
            silver: "ballotbox-silver",
            gold: "ballotbox-gold",
        },
    },
    BillShare: {
        tooltip: (count: number, city: string): string => `Shared ${count} bills for ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Share ${nextCount} bills for ${city}.`,
        icons: {
            blue: "thepeople-blue",
            red: "thepeople-red",
            black: "thepeople-black",
            silver: "thepeople-silver",
            gold: "thepeople-gold",
        },
    },
    Invite: {
        tooltip: (count: number, city: string): string => `Invited ${count} friends in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Invite ${nextCount} friends in ${city}.`,
        icons: {
            blue: "torch-blue",
            red: "torch-red",
            black: "torch-black",
            silver: "torch-silver",
            gold: "torch-gold",
        },
    },
    Sway: {
        tooltip: (count: number, city: string): string => `Earned ${count} sway in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Earn ${nextCount} sway in ${city}.`,
        icons: {
            blue: "crown-blue",
            red: "crown-red",
            black: "crown-black",
            silver: "crown-silver",
            gold: "crown-gold",
        },
    },
};

export const AWARDS = [
    "Voted on a Bill of the Week",
    "Voted on 10 Bills of the Week",
    "Voted on 100 Bills of the Week",
    "Voted on 1000 Bills of the Week",
    "Voted on 10000 Bills of the Week",
    "Shared a Bill of the Week",
    "Shared 10 Bills of the Week",
    "Shared 100 Bills of the Week",
    "Shared 1000 Bills of the Week",
    "Shared 10000 Bills of the Week",
    "Invited 1 Friend",
    "Invited 10 Friends",
    "Invited 100 Friends",
    "Invited 1000 Friends",
    "Invited 10000 Friends",
    "Sway Rank 1",
    "Sway Rank 2",
    "Sway Rank 3",
    "Sway Rank 4",
    "Sway Rank 5",
];

export const AWARD_ICONS = [
    AWARD_ICONS_BY_TYPE.Vote.icons.blue,
    AWARD_ICONS_BY_TYPE.Vote.icons.red,
    AWARD_ICONS_BY_TYPE.Vote.icons.black,
    AWARD_ICONS_BY_TYPE.Vote.icons.silver,
    AWARD_ICONS_BY_TYPE.Vote.icons.gold,
    AWARD_ICONS_BY_TYPE.BillShare.icons.blue,
    AWARD_ICONS_BY_TYPE.BillShare.icons.red,
    AWARD_ICONS_BY_TYPE.BillShare.icons.black,
    AWARD_ICONS_BY_TYPE.BillShare.icons.silver,
    AWARD_ICONS_BY_TYPE.BillShare.icons.gold,
    AWARD_ICONS_BY_TYPE.Invite.icons.blue,
    AWARD_ICONS_BY_TYPE.Invite.icons.red,
    AWARD_ICONS_BY_TYPE.Invite.icons.black,
    AWARD_ICONS_BY_TYPE.Invite.icons.silver,
    AWARD_ICONS_BY_TYPE.Invite.icons.gold,
    AWARD_ICONS_BY_TYPE.Sway.icons.blue,
    AWARD_ICONS_BY_TYPE.Sway.icons.red,
    AWARD_ICONS_BY_TYPE.Sway.icons.black,
    AWARD_ICONS_BY_TYPE.Sway.icons.silver,
    AWARD_ICONS_BY_TYPE.Sway.icons.gold,
];
