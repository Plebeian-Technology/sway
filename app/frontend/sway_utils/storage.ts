import { get } from "lodash";

const IS_COOKIES_ENABLED = !!window.document && "cookie" in window.document;

export const SWAY_STORAGE = {
    Local: {
        User: {
            EmailConfirmed: "@sway/user/EmailConfirmed",
            FirebaseCaching: "@sway/local/user/FirebaseCaching",
            InvitedBy: "@sway/local/user/InvitedBy",
            Registered: "@sway/local/user/Registered",
            SignedIn: "@sway/user/SignedIn",
        },
        BillOfTheWeek: {
            Bill: "@sway/botw/temp/bill",
            Organizations: "@sway/botw/temp/organizations",
            LegislatorVotes: "@sway/botw/temp/legislator_votes",
        },
    },
    Session: {
        User: {
            Locale: "@sway/session/user/Locale",
        },
    },
};

const isIOSSafariSecurityError = (error: Error) => error.name === "SecurityError";

const setCookie = (key: string, value: string) => {
    if (!IS_COOKIES_ENABLED) return;
    window.document.cookie = `${key.trim()}=${value.trim()}`;
};

const getCookie = (key: string): string | null => {
    if (!IS_COOKIES_ENABLED) return null;

    const cookies = window.document.cookie.split(";").reduce(
        (sum, cookie) => {
            const [cookieKey, cookieValue] = cookie.trim().split("=");
            sum[cookieKey.trim() as string] = cookieValue.trim();
            return sum;
        },
        {} as Record<string, string>,
    );
    return get(cookies, key).trim();
};

const deleteCookie = (key: string) => {
    if (!IS_COOKIES_ENABLED) return;

    window.document.cookie = `${key.trim()}=;expires=Thu, 01 Jan 1970 00:00:00 GMT`;
};

// https://stackoverflow.com/a/179514/6410635
export const deleteAllCookies = () => {
    const cookies = window.document.cookie.split(";");

    for (const cookie of cookies) {
        const index = cookie.indexOf("=");
        const key = index > -1 ? cookie.substring(0, index) : cookie;
        window.document.cookie = `${key}=;expires=Thu, 01 Jan 1970 00:00:00 GMT`;
    }
};

export const sessionGet = (key: string): string | null => {
    try {
        return window.sessionStorage?.getItem(key) || null;
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            return getCookie(key);
        }
        throw error;
    }
};

export const sessionSet = (key: string, value: string | undefined): void => {
    if (!value) return;
    try {
        return window.sessionStorage?.setItem(key, value);
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            setCookie(key, value);
        }
        throw error;
    }
};

export const sessionRemove = (key: string) => {
    if (!key) return;
    try {
        return window.sessionStorage?.removeItem(key);
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            deleteCookie(key);
        }
        throw error;
    }
};

export const localGet = (key: string): string | null => {
    try {
        return window.localStorage?.getItem(key) || null;
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            return getCookie(key);
        }
        throw error;
    }
};

export const localSet = (key: string, value: string | undefined): void => {
    if (!value) return;
    try {
        return window.localStorage?.setItem(key, value);
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            setCookie(key, value);
        }
        throw error;
    }
};

export const localRemove = (key: string) => {
    if (!key) return;
    try {
        return window.localStorage?.removeItem(key);
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            deleteCookie(key);
        }
        throw error;
    }
};

export const clear = () => {
    try {
        window.sessionStorage?.clear();
        window.localStorage?.clear();
    } catch (error) {
        // iOS Safari
        if (isIOSSafariSecurityError(error as Error)) {
            deleteAllCookies();
        }
    }
};

const prependSlash = (s: string) => {
    if (!s) return "";
    if (s.startsWith("/")) {
        return s;
    } else {
        return "/" + s;
    }
};

export const getStoragePath = (
    path: string,
    localeName: string,
    directory: "organizations" | "audio" | "images" | "legislators" | "geojson" | "awards",
): string => {
    if (!path) return "";

    const p = prependSlash(path);
    if (path.includes(localeName)) {
        return p.split("?")[0];
    } else {
        return prependSlash(`${prependSlash(localeName)}${prependSlash(directory)}${p.split("?")[0]}`);
    }
};
