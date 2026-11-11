import * as Sentry from "@sentry/react";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

const reportedThisPageLoad = new Set<string>();

// @lat: [[sentry-dedupe-once-per-tab-design#Why reportOnce exists]]
export const reportOnce = (
    key: string,
    message: string,
    { windowMs = ONE_DAY_MS, extra }: { windowMs?: number; extra?: Record<string, unknown> } = {},
): boolean => {
    if (reportedThisPageLoad.has(key)) return false;
    reportedThisPageLoad.add(key);

    const storageKey = `sway.reported.${key}`;

    try {
        const last = Number(window.localStorage.getItem(storageKey));
        if (last && Date.now() - last < windowMs) return false;
        window.localStorage.setItem(storageKey, String(Date.now()));
    } catch {
        // @lat: [[sentry-dedupe-once-per-tab-design#Why reportOnce exists]]
    }

    Sentry.captureMessage(message, { level: "error", fingerprint: [key], extra });
    return true;
};
