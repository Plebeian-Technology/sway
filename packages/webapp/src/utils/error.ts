/** @format */
import * as Sentry from "@sentry/react";
import { IS_PRODUCTION, logDev } from "@sway/utils";
import { IS_MOBILE_PHONE, notify } from ".";

export const DEFAULT_ERROR_MESSAGE = "Please refresh the page and try again.";

export const handleError = (error?: Error, message = ""): void => {
    logDev(error);
    message && logDev(message);
    if (IS_PRODUCTION || IS_MOBILE_PHONE) {
        Sentry.captureMessage(message);
        Sentry.captureException(error);
    }
    notify({
        level: "error",
        title: "Error in Sway",
        message: message || DEFAULT_ERROR_MESSAGE,
    });
};
