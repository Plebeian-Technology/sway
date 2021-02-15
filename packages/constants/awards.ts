import { sway } from "sway";

export const AWARDS = [
    "Voted on a Bill of the Week",
    "Voted on 10 Bills of the Week",
    "Voted on 100 Bills of the Week",
    "Shared a Bill of the Week",
    "Shared 10 Bills of the Week",
    "Shared 100 Bills of the Week",
    "Invited 1 Friend",
    "Invited 10 Friends",
    "Invited 100 Friends",
    "Sway Rank 1",
    "Sway Rank 2",
    "Sway Rank 3",
];

export const AWARD_ICONS = [
    "/avatars/awards/ballotbox.png",
    "/avatars/awards/ballotbox-red.png",
    "/avatars/awards/ballotbox-black.png",
    "/avatars/awards/thepeople.png",
    "/avatars/awards/thepeople.png",
    "/avatars/awards/thepeople.png",
    "/avatars/awards/torch-blue.png",
    "/avatars/awards/torch-red.png",
    "/avatars/awards/torch-black.png",
    "/avatars/awards/crown-blue.png",
    "/avatars/awards/crown-red.png",
    "/avatars/awards/crown-red.png",
];

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
            blue: "/avatars/awards/ballotbox.png",
            red: "/avatars/awards/ballotbox-red.png",
            black: "/avatars/awards/ballotbox-black.png",
            silver: "/avatars/awards/ballotbox.png",
            gold: "/avatars/awards/ballotbox.png",
        },
    },
    BillShare: {
        tooltip: (count: number, city: string): string =>
            `Shared ${count} bills for ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Share ${nextCount} bills for ${city}.`,
        icons: {
            blue: "/avatars/awards/thepeople.png",
            red: "/avatars/awards/thepeople.png",
            black: "/avatars/awards/thepeople.png",
            silver: "/avatars/awards/thepeople.png",
            gold: "/avatars/awards/thepeople.png",
        },
    },
    Invite: {
        tooltip: (count: number, city: string): string =>
            `Invited ${count} friends in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Invite ${nextCount} friends in ${city}.`,
        icons: {
            blue: "/avatars/awards/torch-blue.png",
            red: "/avatars/awards/torch-red.png",
            black: "/avatars/awards/torch-black.png",
            silver: "/avatars/awards/torch-black.png",
            gold: "/avatars/awards/torch-black.png",
        },
    },
    Sway: {
        tooltip: (count: number, city: string): string =>
            `Earned ${count} sway in ${city}.`,
        nextTooltip: (nextCount: number, city: string): string =>
            `Earn ${nextCount} sway in ${city}.`,
        icons: {
            blue: "/avatars/awards/crown-blue.png",
            red: "/avatars/awards/crown-red.png",
            black: "/avatars/awards/crown-red.png",
            silver: "/avatars/awards/crown-red.png",
            gold: "/avatars/awards/crown-red.png",
        },
    },
};
