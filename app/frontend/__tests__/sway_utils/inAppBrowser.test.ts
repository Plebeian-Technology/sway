import { describe, expect, it } from "vitest";

import { IN_APP_BROWSER_TOKENS, isInAppBrowser } from "app/frontend/sway_utils/inAppBrowser";

const USER_AGENTS = {
    instagramIos:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/21E219 Instagram 345.0.1.20.103 (iPhone14,5; iOS 17_4; en_US; en-US; scale=3.00; 1170x2532; 640439420)",
    facebookIos:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/21E219 [FBAN/FBIOS;FBAV/460.0.0.35.108;FBBV/591258412;FBDV/iPhone14,5;FBMD/iPhone;FBSN/iOS;FBSV/17.4;FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]",
    facebookAndroid:
        "Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230901.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/124.0.6367.82 Mobile Safari/537.36 [FB_IAB/FB4A;FBAV/455.0.0.36.113;]",
    tiktokAndroid:
        "Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230901.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/124.0.6367.82 Mobile Safari/537.36 BytedanceWebview/d8a21c6 musical_ly_33.2.0",
    snapchatIos:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Snapchat/12.80.0.40 (like Safari/8617.1.17.10.9, panda)",
    desktopChrome:
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    iosSafari:
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    androidChrome:
        "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36",
};

describe("isInAppBrowser", () => {
    it.each([
        ["Instagram on iOS", USER_AGENTS.instagramIos],
        ["Facebook on iOS", USER_AGENTS.facebookIos],
        ["Facebook on Android", USER_AGENTS.facebookAndroid],
        ["TikTok on Android", USER_AGENTS.tiktokAndroid],
        ["Snapchat on iOS", USER_AGENTS.snapchatIos],
    ])("is true for %s", (_name, userAgent) => {
        expect(isInAppBrowser(userAgent)).toBe(true);
    });

    it.each([
        ["desktop Chrome", USER_AGENTS.desktopChrome],
        ["iOS Safari", USER_AGENTS.iosSafari],
        ["Android Chrome", USER_AGENTS.androidChrome],
    ])("is false for %s", (_name, userAgent) => {
        expect(isInAppBrowser(userAgent)).toBe(false);
    });

    it("reads the browser's user agent when none is given", () => {
        expect(isInAppBrowser()).toBe(
            IN_APP_BROWSER_TOKENS.some((token) => window.navigator.userAgent.includes(token)),
        );
    });

    it("lists every token as one constant", () => {
        expect(IN_APP_BROWSER_TOKENS).toEqual([
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
        ]);
    });
});
