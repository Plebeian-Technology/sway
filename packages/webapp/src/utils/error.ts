/** @format */
import * as Sentry from "@sentry/react";
import { IS_PRODUCTION, logDev } from "@sway/utils";
import { IS_MOBILE_PHONE, notify } from ".";

export const handleError = (error?: Error, message = ""): undefined => {
    console.error(error);
    message && logDev(message);
    if (IS_PRODUCTION || IS_MOBILE_PHONE) {
        Sentry.captureMessage(message);
        Sentry.captureException(error);
    }
    message &&
        notify({
            level: "error",
            title: "Error.",
            message,
        });
    return;
};
