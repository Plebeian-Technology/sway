/** @format */
/* eslint-disable */

// @ts-nocheck

import * as Sentry from "@sentry/react";
import { IS_PRODUCTION } from "@sway/utils";
import { createElement } from "react";
import { toast } from "react-toastify";
import { sway } from "sway";
import SwayToast from "../components/shared/SwayToast";

if (IS_PRODUCTION) {
    window.console.error = Sentry.captureException;
}

const userAgent = navigator.userAgent.toLowerCase();

// TABLET DETECTION - https://stackoverflow.com/a/50195587/6410635
export const IS_TABLET =
    /(ipad|tablet|(android(?!.*mobile))|(windows(?!.*phone)(.*touch))|kindle|playbook|silk|(puffin(?!.*(IP|AP|WP))))/.test(
        userAgent,
    );
export const IS_COMPUTER_WIDTH = window.innerWidth >= 960;

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
        return window.navigator.userAgent.match(toMatchItem);
    });
})();

// BROWSER DETECTION - https://stackoverflow.com/a/26358856/6410635 - in use
const IS_FIREFOX = userAgent.indexOf("firefox") !== -1;
const IS_SAFARI = userAgent.indexOf("safari") !== -1;
const IS_CHROME = userAgent.indexOf("chrome") !== -1;

const TADA_AUDIO = new Audio("https://freesound.org/data/previews/397/397353_4284968-lq.mp3");
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
}): string => {
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
            toastId: `${level}-${title}-${message}`,
            position: IS_MOBILE_PHONE ? toast.POSITION.TOP_CENTER : toast.POSITION.TOP_RIGHT,
            autoClose: duration === 0 ? false : duration ? duration : undefined,
            theme: "colored",
            pauseOnHover: true,
            pauseOnFocusLoss: true,
            closeOnClick: true,
            closeButton: false,
            type: level,
            onClick: onClick || undefined,
            onOpen: () => {
                if (tada) {
                    // TADA_AUDIO && TADA_AUDIO.play().catch(console.error);
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

export const toSelectOption = (label: string, value: string | number): sway.TOption => ({
    label,
    value,
});

export * from "./constants";
export * from "./storage";
export * from "./error";
export * from "./fire";
export * from "./styles";
export {
    // IS_COMPUTER_WIDTH,
    // IS_TABLET_PHONE_WIDTH,
    IS_MOBILE_PHONE,
    notify,
    withTadas,
    chartDimensions,
    GAINED_SWAY_MESSAGE,
    IS_FIREFOX,
    IS_SAFARI,
    IS_CHROME,
};
