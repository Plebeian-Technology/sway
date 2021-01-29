/** @format */
/* eslint-disable */

import * as Sentry from "@sentry/react";
import { isProduction } from "@sway/utils";
import { sway } from "sway";
import { store } from "../redux";
import { setNotification } from "../redux/actions/notificationActions";

if (isProduction) {
    window.console.error = Sentry.captureException;
}

const isComputerWidth = window.innerWidth > 768;
const isTabletPhoneWidth = window.innerWidth <= 768;
const isMobilePhone: boolean = (() => {
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
// @ts-ignore
const IS_FIREFOX = typeof window.InstallTrigger !== "undefined" || navigator.userAgent.match("FxiOS");;

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

const notify = ({
    level,
    message,
    title,
    duration,
}: {
    level: sway.TAlertLevel;
    message: string;
    title: string;
    duration?: number;
}) => {
    store.dispatch(
        setNotification({
            level,
            title,
            message,
            duration,
        }),
    );
};

const chartDimensions = (_default?: number | undefined) => {
    if (_default) return _default;
    if (isMobilePhone) return 325;
    return 400;
};

export * from "./error";
export * from "./fire";
export * from "./styles";
export {
    isComputerWidth,
    isTabletPhoneWidth,
    isMobilePhone,
    notify,
    chartDimensions,
    IS_FIREFOX,
    IS_SAFARI,
    IS_CHROME,
};
