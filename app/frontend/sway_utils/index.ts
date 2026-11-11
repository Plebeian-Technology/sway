import * as Sentry from "@sentry/react";
import toast, { ToastOptions } from "react-hot-toast";
import { ISelectOption, sway } from "sway";
import { IS_MOBILE_PHONE, IS_NOT_PRODUCTION, IS_PRODUCTION } from "app/frontend/sway_constants";

const DEFAULT_ERROR_MESSAGE = "Please refresh the page and try again.";
const MAX_VISIBLE_TOASTS = 5;
const visibleToastIds: string[] = [];

// @lat: [[toasts#The five-toast cap reuses the de-dup identifier]]
const capVisibleToasts = (id: string): void => {
    if (visibleToastIds.includes(id)) return;
    visibleToastIds.push(id);
    if (visibleToastIds.length > MAX_VISIBLE_TOASTS) {
        const oldest = visibleToastIds.shift();
        if (oldest) toast.dismiss(oldest);
    }
};

// @lat: [[browser-error-reporting#An omitted message must not create a second event]]
export const handleError = (error?: Error, message = ""): void => {
    logDev(error);
    if (message) {
        logDev(message);
    }

    if (error?.message?.trim() === "The operation was aborted.") {
        notify({
            level: "info",
            title: "Cancelled",
        });
        return;
    }

    if (IS_PRODUCTION || IS_MOBILE_PHONE) {
        if (message?.trim()) {
            Sentry.captureMessage(message);
        }
        if (error) {
            Sentry.captureException(error);
        }
    }
    notify({
        level: "error",
        title: `Error in Sway. ${message || DEFAULT_ERROR_MESSAGE}`,
    });
};

export const notify = ({
    id,
    level,
    title,
    message,
    duration,
    position,
}: {
    id?: string;
    level: sway.TAlertLevel;
    title: string | React.JSX.Element;
    message?: string;
    duration?: number;
    position?: ToastOptions["position"];
}): string => {
    const icon = (() => {
        return {
            info: "💡",
            warning: "⚠️",
            success: undefined,
            error: undefined,
        }[level];
    })();

    const options = {
        id: id || (typeof title === "string" ? `${level}-${title}-${message}` : undefined),
        position,
        duration,
        icon,
    } as ToastOptions;

    const notification = message && typeof title === "string" ? `${title} ${message}` : title;

    let resultId: string;
    if (level === "success") {
        resultId = toast.success(notification, options);
    } else if (level === "error") {
        resultId = toast.error(notification, options);
    } else {
        resultId = toast(notification, options);
    }

    capVisibleToasts(resultId);

    return resultId;
};

export const withTadas = (string: string) => `🎉 ${string} 🎉`;

export const toSelectOption = (label: string, value: string | number): ISelectOption => ({
    label,
    value,
});
export const logDev = (...args: any[]) => {
    if (IS_NOT_PRODUCTION) {
        const [message, ...extra] = args;

        if (message instanceof DOMException) {
            console.error(message);
        } else if (typeof message === "string") {
            console.log(`(dev) ${message}`, ...extra);
        } else {
            console.log("(dev)", message, ...extra);
        }
    }
};

export const titleize = (string: string, separator = " ", joiner = " ") => {
    if (!string) return "";

    const words = string.toLowerCase().split(separator);

    const toJoin = [];
    for (const word of words) {
        if (word) {
            toJoin.push(word[0].toUpperCase() + word.substring(1));
        }
    }
    return toJoin.join(joiner);
};

export * from "app/frontend/sway_utils/emoji";
export * from "app/frontend/sway_utils/format_eta";
export * from "app/frontend/sway_utils/legislators";
export * from "app/frontend/sway_utils/locales";
export * from "app/frontend/sway_utils/storage";
export * from "app/frontend/sway_utils/webauthn";
export * from "app/frontend/sway_utils/queryParamClearedSignal";
export * from "app/frontend/sway_utils/queryParamNavigationCarry";
