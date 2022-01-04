/** @format */
/* eslint-disable */

// @ts-nocheck

import * as Sentry from "@sentry/react";
import { IS_DEVELOPMENT, IS_PRODUCTION } from "@sway/utils";
import { createElement } from "react";
import { toast } from "react-toastify";
import { sway } from "sway";
import SwayToast from "../components/shared/SwayToast";

if (IS_PRODUCTION) {
    window.console.error = Sentry.captureException;
}

const IS_COMPUTER_WIDTH = window.innerWidth > 768;
const IS_TABLET_PHONE_WIDTH = window.innerWidth <= 768;
const IS_MOBILE_PHONE: boolean = (() => {
    const toMatch = [
        /Android/i,
        /webOS/i,
        /iPhone/i,
        /iPad/i,
        /iPod/i,
        /BlackBerry/i,
        /Windows Phone/i,
    ];

    return toMatch.some((toMatchItem) => {
        return navigator.userAgent.match(toMatchItem);
    });
})();

// BROWSER DETECTION - https://stackoverflow.com/a/9851769/6410635
// Firefox 1.0+
const IS_FIREFOX = // @ts-ignore
    typeof window.InstallTrigger !== "undefined" ||
    navigator.userAgent.match("FxiOS");

// Safari 3.0+ "[object HTMLElementConstructor]"
// @ts-ignore
const IS_SAFARI = // @ts-ignore
    /constructor/i.test(window.HTMLElement) ||
    (function (p) {
        return p.toString() === "[object SafariRemoteNotification]";
    })(
        !window["safari"] || // @ts-ignore
            (typeof window.safari !== "undefined" &&
                window["safari"].pushNotification),
    );

// Chrome 1 - 79
const IS_CHROME = // @ts-ignore
    !!window.chrome && (!!window.chrome.webstore || !!window.chrome.runtime);

const TADA_AUDIO = new Audio(
    "https://freesound.org/data/previews/397/397353_4284968-lq.mp3",
);
TADA_AUDIO.load();

const GAINED_SWAY_MESSAGE = "You gained some Sway!";

const notify = ({
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
}) => {
    return toast(
        ({ closeToast, toastProps }) =>
            createElement(SwayToast, {
                title: title,
                message: message,
                tada: Boolean(tada),
                closeToast: closeToast,
                toastProps: toastProps,
            }),
        {
            position: IS_MOBILE_PHONE
                ? toast.POSITION.TOP_CENTER
                : toast.POSITION.TOP_RIGHT,
            autoClose: duration === 0 ? false : duration ? duration : undefined,
            theme: "colored",
            type: level,
            onClick: onClick || undefined,
            onOpen: () => {
                if (tada) {
                    TADA_AUDIO && TADA_AUDIO.play().catch(console.error);
                }
            },
        },
    );
};

const withTadas = (string: string) => `🎉 ${string} 🎉`;

const chartDimensions = (_default?: number | undefined) => {
    if (_default) return _default;
    if (IS_MOBILE_PHONE) return 325;
    return 400;
};

export * from "./constants";
export * from "./error";
export * from "./fire";
export * from "./styles";
export {
    IS_COMPUTER_WIDTH,
    IS_TABLET_PHONE_WIDTH,
    IS_MOBILE_PHONE,
    notify,
    withTadas,
    chartDimensions,
    GAINED_SWAY_MESSAGE,
    IS_FIREFOX,
    IS_SAFARI,
    IS_CHROME,
};
