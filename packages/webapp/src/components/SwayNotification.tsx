/** @format */

import { ALERT_DELAY } from "@sway/constants";
import Snackbar from "@material-ui/core/Snackbar";
import { AlertTitle } from "@material-ui/lab";
import MuiAlert, { AlertProps } from "@material-ui/lab/Alert";
import React from "react";
import { useDispatch } from "react-redux";
import { useNotification } from "../hooks/notification";
import { setNotification } from "../redux/actions/notificationActions";

const Alert = (props: AlertProps) => {
    return <MuiAlert elevation={6} variant="filled" {...props} />;
};

const SwayNotification: React.FC = () => {
    const dispatch = useDispatch();
    const notificationState = useNotification();

    const { notification } = notificationState;

    const handleClose = () => {
        dispatch(setNotification(null));
    };

    if (!notification) return null;

    const setDuration = (): number => {
        if (typeof notification?.duration === "number") {
           if (notification.duration === 0) {
               return 999999;
           }
           return notification.duration;
        }
        return ALERT_DELAY;
    }

    return (
        <Snackbar
            className={"notification-snackbar"}
            open={!!notification}
            autoHideDuration={setDuration()}
            onClose={handleClose}
            anchorOrigin={{ vertical: "top", horizontal: "right" }}
        >
            <Alert
                onClose={handleClose}
                severity={notification && notification.level}
            >
                <AlertTitle style={{ fontWeight: "bold" }}>{notification && notification.title}</AlertTitle>
                {notification?.message && <span style={{ fontWeight: "bold" }}>{notification.message}</span>}
            </Alert>
        </Snackbar>
    );
};

export default SwayNotification;
