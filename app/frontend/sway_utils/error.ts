/** @format */

import * as Sentry from "@sentry/react";
import { IS_MOBILE_PHONE, IS_PRODUCTION } from "app/frontend/sway_constants";
import { logDev, notify } from "app/frontend/sway_utils";


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
