// @lat: [[settings-groups#Settings groups#Why the frontend's IS_PRODUCTION reads the build, not the hostname]]
export const IS_PRODUCTION = import.meta.env.PROD;
export const IS_DEVELOPMENT = !IS_PRODUCTION;
export const IS_NOT_PRODUCTION = IS_DEVELOPMENT;

export const IS_MOBILE_PHONE: boolean = (() => {
    const toMatch = [/Android/i, /webOS/i, /iPhone/i, /iPad/i, /iPod/i, /BlackBerry/i, /Windows Phone/i];

    return toMatch.some((toMatchItem) => {
        return !!toMatchItem.exec(window.navigator.userAgent);
    });
})();

export const CURRENT_CONGRESS_NUMBER = 119;

export const GITHUB_LINK = "https://github.com/Plebeian-Technology/sway";

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

export type TSupport = (typeof Support)[keyof typeof Support];

export * from "app/frontend/sway_constants/swayLocales";
export * from "app/frontend/sway_constants/navigation";
export * from "app/frontend/sway_constants/parityCopy";
export * from "app/frontend/sway_constants/routes";
