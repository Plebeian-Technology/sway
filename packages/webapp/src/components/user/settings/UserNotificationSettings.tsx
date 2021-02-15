/** @format */

import {
    createStyles,
    makeStyles,
    Typography
} from "@material-ui/core";
import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import SwayCheckbox from "../../shared/SwayCheckbox";

interface IProps {
    notificationFrequency: sway.TNotificationFrequency;
    setNotificationFrequency: (frequency: sway.TNotificationFrequency) => void;
    notificationType: sway.TNotificationType;
    setNotificationType: (type: sway.TNotificationType) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        section: {
            margin: 10,
        },
        column: {
            display: "flex",
            flexDirection: "column",
            justifyContent: "flex-start",
            alignItems: "flex-start",
        },
        container: {
            textAlign: "center",
            margin: "0px 20px",
        },
    }),
);

const UserNotificationSettings: React.FC<IProps> = ({
    notificationFrequency,
    setNotificationFrequency,
    notificationType,
    setNotificationType,
}) => {
    const classes = useStyles();

    const setDaily = () =>
        setNotificationFrequency(NOTIFICATION_FREQUENCY.Daily);
    const setWeekly = () =>
        setNotificationFrequency(NOTIFICATION_FREQUENCY.Weekly);
    const setOff = () => {
        setNotificationFrequency(NOTIFICATION_FREQUENCY.Off);
        setNotificationType(null);
    };

    const setEmail = () => {
        if (notificationType === NOTIFICATION_TYPE.Email) {
            setNotificationType(null);
        } else {
            setNotificationType(NOTIFICATION_TYPE.Email);
        }
    };

    return (
        <div className={classes.section}>
            {" "}
            <div>
                <Typography variant={"h4"} component={"h4"}>
                    Notification Frequency
                </Typography>
            </div>
            <div className={classes.column}>
                <div className={classes.container}>
                    <SwayCheckbox
                        name={"daily"}
                        id={"daily"}
                        label={"Daily"}
                        checked={
                            notificationFrequency ===
                            NOTIFICATION_FREQUENCY.Daily
                        }
                        onChange={setDaily}
                        disabled={false}
                    />
                </div>
                <div className={classes.container}>
                    <SwayCheckbox
                        name={"weekly"}
                        id={"weekly"}
                        label={"Weekly/Once"}
                        checked={
                            notificationFrequency ===
                            NOTIFICATION_FREQUENCY.Weekly
                        }
                        onChange={setWeekly}
                        disabled={false}
                    />
                </div>
                <div className={classes.container}>
                    <SwayCheckbox
                        name={"off"}
                        id={"off"}
                        label={"Off"}
                        checked={
                            notificationFrequency === NOTIFICATION_FREQUENCY.Off
                        }
                        onChange={setOff}
                        disabled={false}
                    />
                </div>
            </div>
            <div>
                <Typography variant={"h4"} component={"h4"}>
                    Notification Type
                </Typography>
            </div>
            <div className={classes.column}>
                <div className={classes.container}>
                    <SwayCheckbox
                        name={"email"}
                        id={"email"}
                        label={"Email"}
                        checked={notificationType === NOTIFICATION_TYPE.Email}
                        onChange={setEmail}
                        disabled={
                            notificationFrequency === NOTIFICATION_FREQUENCY.Off
                        }
                    />
                </div>
            </div>
        </div>
    );
};

export default UserNotificationSettings;
