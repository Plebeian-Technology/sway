/** @format */
import * as Sentry from "@sentry/react";
import { notify, IS_DEVELOPMENT, isProduction } from ".";

export const handleError = (error?: Error, message = ""): void => {
    if (IS_DEVELOPMENT && error) {
        if (message) console.log(message);
        console.error(error);
    } else if (isProduction) {
        Sentry.captureMessage(message);
        Sentry.captureException(error);
    }
    message &&
        notify({
            level: "error",
            title: "Error",
            message,
        });
};

export const UserExistsOnInsertError = new Error(
    "Could not complete registration.",
);
