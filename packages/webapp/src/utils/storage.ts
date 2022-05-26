import { get } from "@sway/utils";

const IS_COOKIES_ENABLED = !!window.document && "cookie" in window.document;

const isIOSSafariSecurityError = (error: Error) => error.name === "SecurityError";

const setCookie = (key: string, value: string) => {
    if (!IS_COOKIES_ENABLED) return;
    window.document.cookie = `${key.trim()}=${value.trim()}`;
};

const getCookie = (key: string): string | null => {
    if (!IS_COOKIES_ENABLED) return null;

    const cookies = window.document.cookie.split(";").reduce((sum, cookie) => {
        const [cookieKey, cookieValue] = cookie.trim().split("=");
        sum[cookieKey.trim()] = cookieValue.trim();
        return sum;
    });
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
