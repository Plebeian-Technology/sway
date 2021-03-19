/** @format */
import * as Sentry from "@sentry/react";
import { IS_DEVELOPMENT, IS_PRODUCTION } from "@sway/utils"
import { notify } from ".";

export const handleError = (error?: Error, message = ""): undefined => {
    if (IS_DEVELOPMENT && error) {
        if (message) console.log(message);
        console.error(error);
    } else if (IS_PRODUCTION) {
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
