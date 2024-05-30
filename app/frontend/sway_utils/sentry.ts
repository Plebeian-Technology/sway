import {
    captureException,
    init,
    replayIntegration
} from "@sentry/react";
import { logDev } from "app/frontend/sway_utils";
import { noop } from "lodash";

export const SentryUtil = {
    init: () => {
        if (import.meta.env.MODE === "production") {
            window.console.log = noop;
            window.console.dir = noop;
            window.console.table = noop;
            window.console.warn = noop;
            window.console.error = captureException;
        }

        if (
            import.meta.env.MODE === "production" &&
            import.meta.env.VITE_SENTRY_IO_ID &&
            import.meta.env.VITE_SENTRY_IO_ROUTE
        ) {
            logDev("Initializing sentry.io error tracing on prod/admin");
            try {
                init({
                    dsn: `https://${import.meta.env.VITE_SENTRY_IO_ID}.ingest.sentry.io/${
                        import.meta.env.VITE_SENTRY_IO_ROUTE
                    }`,
                    integrations: [
                        // https://docs.sentry.io/platforms/javascript/guides/react/configuration/integrations/
                        replayIntegration(),
                    ],

                    // https://github.com/getsentry/sentry-javascript/issues/3440
                    ignoreErrors: [
                        "Non-Error promise rejection",
                        "AxiosError",
                        "Network Error",
                        "ResizeObserver loop limit exceeded",
                        "webkit-masked-url",
                        "react-to-print/lib/index",
                        "<unknown>",
                        "undefined is not an object (evaluating 'a.N')",
                        "clone is not a function",

                        // Common things to ignore - https://gist.github.com/impressiver/5092952
                        // https://docs.sentry.io/platforms/javascript/configuration/filtering/
                        // Random plugins/extensions
                        "top.GLOBALS",
                        // See: http://blog.errorception.com/2012/03/tale-of-unfindable-js-error.html
                        "originalCreateNotification",
                        "canvas.contentDocument",
                        "MyApp_RemoveAllHighlights",
                        "http://tt.epicplay.com",
                        "Can't find variable: ZiteReader",
                        "jigsaw is not defined",
                        "ComboSearch is not defined",
                        "http://loading.retry.widdit.com/",
                        "atomicFindClose",
                        // Facebook borked
                        "fb_xd_fragment",
                        // ISP "optimizing" proxy - `Cache-Control: no-transform` seems to
                        // reduce this. (thanks @acdha)
                        // See http://stackoverflow.com/questions/4113268
                        "bmi_SafeAddOnload",
                        "EBCallBackMessageReceived",
                        // See http://toolbar.conduit.com/Developer/HtmlAndGadget/Methods/JSInjection.aspx
                        "conduitPage",
                        // Generic error code from errors outside the security sandbox
                        // You can delete this if using raven.js > 1.0, which ignores these automatically.
                        "Script error.",
                        // Avast extension error
                        "_avast_submit",
                    ],

                    // Common things to ignore - https://gist.github.com/impressiver/5092952
                    // https://docs.sentry.io/platforms/javascript/configuration/filtering/
                    denyUrls: [
                        // Facebook flakiness
                        /graph\.facebook\.com/i,
                        // Facebook blocked
                        /connect\.facebook\.net\/en_US\/all\.js/i,
                        // Woopra flakiness
                        /eatdifferent\.com\.woopra-ns\.com/i,
                        /static\.woopra\.com\/js\/woopra\.js/i,
                        // Chrome extensions
                        /extensions\//i,
                        /^chrome:\/\//i,
                        /^chrome-extension:\/\//i,
                        // Other plugins
                        /127\.0\.0\.1:4001\/isrunning/i, // Cacaoweb
                        /webappstoolbarba\.texthelp\.com\//i,
                        /metrics\.itunes\.apple\.com\.edgesuite\.net\//i,

                        // add this to ignore safari webkit
                        /.*@webkit-masked-url.*/,
                    ],

                    // We recommend adjusting this value in production, or using tracesSampler
                    // for finer control
                    // Set tracesSampleRate to 1.0 to capture 100%
                    // of transactions for performance monitoring.
                    tracesSampleRate: 1.0,

                    // Capture Replay for 10% of all sessions,
                    // plus for 100% of sessions with an error
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
