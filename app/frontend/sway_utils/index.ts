
/** @format */
/* eslint-disable */

import * as Sentry from "@sentry/react";
import { IS_MOBILE_PHONE, IS_NOT_PRODUCTION, IS_PRODUCTION } from "app/frontend/sway_constants";
import toast from "react-hot-toast";
import { sway } from "sway";

declare global {
    interface Array<T> {
        first(): T;
        last(): T;
    }
}

if (IS_PRODUCTION) {
    window.console.error = Sentry.captureException;
}

if (!Array.prototype.first) {
    Array.prototype.first = function (defaultValue?: any) {
        return this[0] || defaultValue;
    };
}

if (!Array.prototype.last) {
    Array.prototype.last = function (defaultValue?: any) {
        return this[this.length - 1] || defaultValue;
    };
}

const TADA_AUDIO = new Audio("https://freesound.org/data/previews/397/397353_4284968-lq.mp3");
TADA_AUDIO.load();

const GAINED_SWAY_MESSAGE = "You gained some Sway!";

export const notify = ({
    level,
    title,
    message,
    tada,
    duration,
    onClick,
}: {
    level: sway.TAlertLevel;
    title: string;
    message?: string;
    tada?: boolean;
    duration?: number;
    onClick?: () => void;
}): string => {
    const options = {
        toastId: `${level}-${title}-${message}`,
        // position: IS_MOBILE_PHONE ? toast.POSITION.TOP_CENTER : toast.POSITION.TOP_RIGHT,
        autoClose: duration === 0 ? false : duration || undefined,
        theme: "colored",
        pauseOnHover: true,
        pauseOnFocusLoss: true,
        closeOnClick: true,
        closeButton: false,
        type: level,
        onOpen: () => {
            if (tada) {
                // TADA_AUDIO && TADA_AUDIO.play().catch(console.error);
            }
        },
    };
    // if (onClick) {
    //     options["onClick"] = onClick;
    // }

    return toast(
        title
    );
    // return toast(
    //     ({ closeToast, toastProps }) =>
    //         createElement(SwayToast, {
    //             title: title,
    //             message: message,
    //             tada: Boolean(tada),
    //             closeToast: closeToast,
    //             toastProps: toastProps,
    //         }),
    //     options,
    // );
};

export const withTadas = (string: string) => `🎉 ${string} 🎉`;

export const chartDimensions = (_default?: number | undefined) => {
    if (_default) return _default;
    if (IS_MOBILE_PHONE) return 325;
    return 400;
};

export const toSelectOption = (label: string, value: string | number): sway.TOption => ({
    label,
    value,
});




export const logDev = (...args: any[]) => {
    if (IS_NOT_PRODUCTION) {
        const [message, ...extra] = args;
        if (typeof message === "string") {
            console.log(`(dev) ${message}`, ...extra);
        } else {
            console.log("(dev)", message, ...extra);
        }
    }
};

export const isEmptyObject = (obj: any) => {
    if (!obj) return true;

    if (typeof obj === "number" || typeof obj === "string") return false;

    if (Array.isArray(obj) && obj.length === 0) return true;

    for (const key in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) return false; // NOSONAR
    }
    return true;
};

export const createNotificationDate = () => {
    const date = new Date();
    return date.toISOString().split("T")[0];
};

export const isNumber = (value: any) => typeof value === "number" && isFinite(value);

export const isNumeric = (string: string | null | undefined): boolean => {
    if (!string) return false;

    if (typeof string === "number") {
        return true;
    }

    if (typeof string !== "string") {
        return false;
    }

    return string.match(/\d+/) !== null;
};

export const flatten = (arrays: any[]): any[] => {
    return [].concat(...arrays);
};

export const isFirebaseUser = (user: any): boolean => {
    return user && (user.za || user.refreshToken);
};

export const withNumberSuffix = (n: number) => {
    const s = String(n);
    if (!s) return n;
    if (n <= 0) return n;
    if (s.endsWith("1") && n !== 11) return `${s}st`;
    if (s.endsWith("2") && n !== 12) return `${s}nd`;
    if (s.endsWith("3") && n !== 13) return `${s}rd`;
    return `${s}th`;
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

export const formatPhone = (phone: string): string => {
    const _withoutSpecialCharacters = phone.replace(/\D/g, "");
    if (_withoutSpecialCharacters.length !== 10) {
        console.error(
            "Phone without special characters is not 10 digits -",
            _withoutSpecialCharacters,
        );
    }
    return (
        "+1 " +
        _withoutSpecialCharacters
            .split("")
            .map((char: string, index: number) => {
                if (index === 0) {
                    return `(${char}`;
                }
                if (index === 2) {
                    return `${char}) `;
                }
                if (index === 5) {
                    return `${char}-`;
                }
                return char;
            })
            .join("")
    );
};


export * from "./bills";
export * from "./charts";
export * from "./emoji";
export * from "./error";
export * from "./fire";
export * from "./legislators";
export * from "./locales";
export * from "./storage";
export * from "./stringSimilarity";
export * from "./styles";
export * from "./users";
