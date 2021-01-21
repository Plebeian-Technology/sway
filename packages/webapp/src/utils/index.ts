/** @format */
/* eslint-disable */

import * as Sentry from "@sentry/react";
import { isProduction } from "@sway/utils"
import { sway } from "sway";
import { store } from "../redux";
import { setNotification } from "../redux/actions/notificationActions";

if (isProduction) {
    window.console.error = Sentry.captureException;
}

const isComputerWidth = window.innerWidth > 768;
const isTabletPhoneWidth = window.innerWidth <= 768;
const isPhoneWidth = window.innerWidth <= 414;

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
        })
    );
};

const chartDimensions = (_default?: number | undefined) => {
    if (_default) return _default;
    if (isPhoneWidth) return 325;
    return 400;
}

export * from "./error";
export * from "./fire";
export * from "./styles";
export {
    isComputerWidth,
    isTabletPhoneWidth,
    isPhoneWidth,
    notify,
    chartDimensions,
};
