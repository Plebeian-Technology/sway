/** @format */
import * as Sentry from "@sentry/react";
import { IS_PRODUCTION, logDev } from "@sway/utils";
import { notify } from ".";

export const handleError = (error?: Error, message = ""): undefined => {
    console.error(error);
    message && logDev(message);
    if (IS_PRODUCTION) {
        Sentry.captureMessage(message);
        Sentry.captureException(error);
    }
    message &&
        notify({
            level: "error",
            message: `Error. ${message}`,
        });
    return;
};
