import * as Sentry from "@sentry/react";
import { logDev } from "app/frontend/sway_utils";
import { isLocalErrorCollectorDsn } from "app/frontend/sway_utils/local_error_dsn";
import { scrubErrorEvent } from "app/frontend/sway_utils/scrub_error_event";
import { noop } from "lodash";

// @lat: [[browser-error-reporting#Development reports stay on this machine]]
const initLocalErrorCollector = () => {
    const dsn = import.meta.env.VITE_RUSTRAK_DSN as string | undefined;

    if (!dsn) {
        // @lat: [[browser-error-reporting#Development reports stay on this machine#Where each development address is read]]
        logDev(
            "No VITE_RUSTRAK_DSN set — browser errors stay in the console only. " +
                "If you expected them to be recorded, the vite container was probably started " +
                "without the address: re-run `dip run dev`.",
        );
        return;
    }

    if (!isLocalErrorCollectorDsn(dsn)) {
        // @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
        console.warn(
            "VITE_RUSTRAK_DSN does not point at this machine, so error reporting is OFF. " +
                "Only localhost, 127.0.0.1, ::1, host.docker.internal and rustrak are accepted.",
        );
        return;
    }

    Sentry.init({
        dsn,
        // @lat: [[local-error-reporting-design#Why config.environment is set explicitly]]
        environment: import.meta.env.MODE,
        // @lat: [[local-error-reporting-design#Why initLocalErrorCollector drops the BrowserSession integration]]
        integrations: (defaults) => defaults.filter((i) => i.name !== "BrowserSession"),
        tracesSampleRate: 0,
        beforeSend: scrubErrorEvent,
        sendDefaultPii: false,
    });

    logDev("Reporting browser errors to the local collector.");
};

export const TRANSIENT_NETWORK_ERRORS = [
    "Load failed",
    "Failed to fetch",
    "NetworkError when attempting to fetch resource",
] as const;

// @lat: [[sway-error-scrubber-design#Why production web beforeSend delegates to scrubErrorEvent and masks replays]]
export const beforeSend = (event: Sentry.ErrorEvent, _hint?: Sentry.EventHint): Sentry.ErrorEvent | null => {
    const values = event.exception?.values ?? [];
    for (const val of values) {
        const message = val.value ?? "";
        if (message.startsWith("Unable to preload CSS for ")) {
            return null;
        }
        if (TRANSIENT_NETWORK_ERRORS.some((transient) => message.includes(transient))) {
            return null;
        }
        if (
            (!message || message === "undefined" || message === "null") &&
            (val.stacktrace?.frames?.length ?? 0) === 0
        ) {
            return null;
        }
    }
    return scrubErrorEvent(event);
};

const formatConsoleArg = (arg: unknown): string => {
    if (typeof arg === "string") return arg;
    if (typeof arg === "number" || typeof arg === "boolean" || typeof arg === "bigint" || typeof arg === "symbol") {
        return arg.toString();
    }
    if (arg instanceof Error) return arg.message;
    try {
        return JSON.stringify(arg) ?? "";
    } catch {
        return "[Unserializable]";
    }
};

export const SentryUtil = {
    beforeSend,
    init: async () => {
        if (import.meta.env.MODE === "production") {
            window.console.log = noop;
            window.console.dir = noop;
            window.console.table = noop;
            window.console.warn = noop;
            window.console.error = (...args: unknown[]) => {
                const nonNilArgs = args.filter((arg) => arg !== null && arg !== undefined);
                if (nonNilArgs.length === 0) return;
                const errorArg = nonNilArgs.find((arg): arg is Error => arg instanceof Error);
                if (errorArg) {
                    const otherArgs = nonNilArgs.filter((arg) => arg !== errorArg);
                    Sentry.captureException(
                        errorArg,
                        otherArgs.length > 0 ? { extra: { args: otherArgs } } : undefined,
                    );
                } else {
                    const message = nonNilArgs.map(formatConsoleArg).join(" ").trim();
                    if (message.length > 0 && message !== "undefined" && message !== "null") {
                        Sentry.captureMessage(message);
                    }
                }
            };
        }

        if (import.meta.env.MODE !== "production") {
            initLocalErrorCollector();
            return;
        }

        // @lat: [[browser-error-reporting#Why the browser DSN is a build secret]]
        const dsn = import.meta.env.VITE_SENTRY_DSN as string | undefined;

        if (import.meta.env.MODE === "production" && dsn) {
            logDev("Initializing sentry.io error tracing on prod/admin");
            try {
                Sentry.init({
                    dsn,
                    beforeSend: SentryUtil.beforeSend,
                    integrations: [
                        Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
                        Sentry.browserTracingIntegration(),
                    ],

                    ignoreErrors: [
                        "Non-Error promise rejection",
                        "ResizeObserver loop limit exceeded",
                        "webkit-masked-url",
                        "react-to-print/lib/index",
                        "undefined is not an object (evaluating 'a.N')",
                        "clone is not a function",
                        "top.GLOBALS",
                        "originalCreateNotification",
                        "canvas.contentDocument",
                        "MyApp_RemoveAllHighlights",
                        "http://tt.epicplay.com",
                        "Can't find variable: ZiteReader",
                        "jigsaw is not defined",
                        "ComboSearch is not defined",
                        "http://loading.retry.widdit.com/",
                        "atomicFindClose",
                        "fb_xd_fragment",
                        "bmi_SafeAddOnload",
                        "EBCallBackMessageReceived",
                        "conduitPage",
                        "Script error.",
                        "_avast_submit",
                    ],

                    denyUrls: [
                        /graph\.facebook\.com/i,
                        /connect\.facebook\.net\/en_US\/all\.js/i,
                        /eatdifferent\.com\.woopra-ns\.com/i,
                        /static\.woopra\.com\/js\/woopra\.js/i,
                        /extensions\//i,
                        /^chrome:\/\//i,
                        /^chrome-extension:\/\//i,
                        /127\.0\.0\.1:4001\/isrunning/i,
                        /webappstoolbarba\.texthelp\.com\//i,
                        /metrics\.itunes\.apple\.com\.edgesuite\.net\//i,
                        /.*@webkit-masked-url.*/,
                    ],

                    tracesSampleRate: 1.0,

                    replaysSessionSampleRate: 0.1,
                    replaysOnErrorSampleRate: 1.0,
                });
            } catch (error) {
                logDev("Failed to initialize sentry.io on prod/admin");
                console.warn(error);
            }
        } else {
            logDev("Skip initializing sentry.io");
        }
    },
};
