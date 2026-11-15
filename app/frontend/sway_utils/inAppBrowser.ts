export const IN_APP_BROWSER_TOKENS = [
    "Instagram",
    "FBAN",
    "FBAV",
    "FB_IAB",
    "FBIOS",
    "Messenger",
    "musical_ly",
    "BytedanceWebview",
    "TikTok",
    "Snapchat",
    "LinkedInApp",
];

export const isInAppBrowser = (userAgent: string = window.navigator.userAgent): boolean =>
    IN_APP_BROWSER_TOKENS.some((token) => userAgent.includes(token));
