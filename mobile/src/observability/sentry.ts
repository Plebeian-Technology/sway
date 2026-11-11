import * as Sentry from "@sentry/react-native";
import Constants from "expo-constants";
import { logDev } from "../utils/logging";
import { dsnForThisPlatform, isLocalErrorCollectorDsn } from "./local_error_dsn";
import { scrubErrorEvent } from "./scrub_error_event";

// @lat: [[mobile-sentry-init-design#Mobile Sentry init design]]

type Breadcrumb = {
    category?: string;
    message?: string;
    data?: Record<string, unknown>;
};

const PUSH_TOKEN_METHOD_RE = /getDevicePushTokenAsync/i;
const DEVICES_URL_RE = /\/api\/v1\/devices(\b|\/|\?|$)/i;

// @lat: [[sway-error-scrubber-design#Why the mobile breadcrumb hook drops push-token entries]]
export function scrubPushTokenBreadcrumb(bc: Breadcrumb | null | undefined): Breadcrumb | null {
    if (!bc) return null;
    const message = typeof bc.message === "string" ? bc.message : "";
    if (PUSH_TOKEN_METHOD_RE.test(message)) return null;

    const data = bc.data ?? {};
    for (const key of Object.keys(data)) {
        const value = data[key];
        if (typeof value === "string") {
            if (PUSH_TOKEN_METHOD_RE.test(value)) return null;
            if (key.toLowerCase() === "url" && DEVICES_URL_RE.test(value)) return null;
        }
    }
    return bc;
}

// @lat: [[mobile-sentry-init-design#Why debug: true only in the local-collector branch]]
function initLocalErrorCollector(): void {
    const stored = (Constants.expoConfig?.extra as { rustrakDsn?: string } | undefined)?.rustrakDsn;

    if (!stored) {
        // @lat: [[console-channels#Why warn and error are left alone]]
        logDev(
            "No RUSTRAK_DSN_MOBILE set — errors stay in the console only. " +
                "If you expected them to be recorded, Metro was probably started from a shell " +
                "where mise had not exported it: start it from inside the repo.",
        );
        return;
    }

    const dsn = dsnForThisPlatform(stored);

    if (!isLocalErrorCollectorDsn(dsn)) {
        console.warn(
            `RUSTRAK_DSN_MOBILE does not point at the dev machine (${dsn}), so error reporting is OFF. ` +
                "A physical device cannot reach the collector; use a simulator or emulator.",
        );
        return;
    }

    Sentry.init({
        dsn,
        // @lat: [[mobile-sentry-init-design#Why debug: true only in the local-collector branch]]
        debug: true,
        environment: "development",
        tracesSampleRate: 0,
        beforeBreadcrumb: (bc) => scrubPushTokenBreadcrumb(bc as Breadcrumb),
        beforeSend: (event) => scrubErrorEvent(event),
        sendDefaultPii: false,
        // @lat: [[mobile-sentry-init-design#Why the replay opt-out sits at the root, not under _experiments]]
        replaysSessionSampleRate: 0,
        replaysOnErrorSampleRate: 0,
    });
}

export function initSentry(): void {
    if (__DEV__) {
        initLocalErrorCollector();
        return;
    }

    const dsn = (Constants.expoConfig?.extra as { sentryDsn?: string } | undefined)?.sentryDsn;
    if (!dsn) return;
    Sentry.init({
        dsn,
        tracesSampleRate: 0.2,
        beforeBreadcrumb: (bc) => scrubPushTokenBreadcrumb(bc as Breadcrumb),
        beforeSend: (event) => scrubErrorEvent(event),
        sendDefaultPii: false,
        replaysSessionSampleRate: 0,
        replaysOnErrorSampleRate: 0,
    });
}
