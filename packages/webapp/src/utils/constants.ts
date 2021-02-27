import { IS_DEVELOPMENT } from "@sway/utils";
import { sway } from "sway";

const withBucket = (award: string) =>
    IS_DEVELOPMENT
        ? `https://firebasestorage.googleapis.com/v0/b/sway-dev-3187f.appspot.com/o/awards%2F${award}.png?alt=media`
        : `https://firebasestorage.googleapis.com/v0/b/sway-7947e.appspot.com/o/awards%2F${award}.png?alt=media`;

export const AWARD_TYPES: {
    Vote: sway.TAwardType;
    BillShare: sway.TAwardType;
    Invite: sway.TAwardType;
    Sway: sway.TAwardType;
} = {
    Vote: "Vote",
    BillShare: "BillShare",
    Invite: "Invite",
    Sway: "Sway",
};

export const AWARD_ICONS_BY_TYPE: sway.TAwardByType = {
    Vote: {
        tooltip: (count: number, city: string): string =>
            `Voted on ${count} bills in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Vote on ${nextCount} bills in ${city}.`,
        icons: {
            blue: withBucket("ballotbox-blue"),
            red: withBucket("ballotbox-red"),
            black: withBucket("ballotbox-black"),
            silver: withBucket("ballotbox-silver"),
            gold: withBucket("ballotbox-gold"),
        },
    },
    BillShare: {
        tooltip: (count: number, city: string): string =>
            `Shared ${count} bills for ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Share ${nextCount} bills for ${city}.`,
        icons: {
            blue: withBucket("thepeople-blue"),
            red: withBucket("thepeople-red"),
            black: withBucket("thepeople-black"),
            silver: withBucket("thepeople-silver"),
            gold: withBucket("thepeople-gold"),
        },
    },
    Invite: {
        tooltip: (count: number, city: string): string =>
            `Invited ${count} friends in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Invite ${nextCount} friends in ${city}.`,
        icons: {
            blue: withBucket("torch-blue"),
            red: withBucket("torch-red"),
            black: withBucket("torch-black"),
            silver: withBucket("torch-silver"),
            gold: withBucket("torch-gold"),
        },
    },
    Sway: {
        tooltip: (count: number, city: string): string =>
            `Earned ${count} sway in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Earn ${nextCount} sway in ${city}.`,
        icons: {
            blue: withBucket("crown-blue"),
            red: withBucket("crown-red"),
            black: withBucket("crown-black"),
            silver: withBucket("crown-silver"),
            gold: withBucket("crown-gold"),
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
