/** @format */

import { Button, Checkbox, Typography } from "@material-ui/core";
import { Save } from "@material-ui/icons";
import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import { swayFireClient, notify } from "../../utils";
import { IS_DEVELOPMENT } from "@sway/utils";

interface IProps {
    userWithSettingsAdmin: sway.IUserWithSettingsAdmin | undefined;
}

const UserSettings: React.FC<IProps> = ({ userWithSettingsAdmin }) => {
    const user = userWithSettingsAdmin?.user;
    const settings = userWithSettingsAdmin?.settings;

    const [notificationFrequency, setNotificationFrequency] = React.useState<
        0 | 1 | 2 | null
    >(
        typeof settings?.notificationFrequency === "number"
            ? settings?.notificationFrequency
            : null,
    );
    const [notificationType, setNotificationType] = React.useState<
        0 | 1 | 2 | null
    >(
        typeof settings?.notificationType === "number"
            ? settings?.notificationType
            : null,
    );

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

    const handleSubmit = async () => {
        if (!user?.uid || user.isAnonymous || !settings) return;

        const values: Partial<sway.IUserSettings> = {
            notificationFrequency,
            notificationType,
        };

        swayFireClient()
            .userSettings(user?.uid)
            .update({
                ...settings,
                ...values,
            })
            .then(() => {
                notify({
                    level: "success",
                    title: "Updated Settings",
                    message: "",
                });
            })
            .catch((error: Error) => {
                if (IS_DEVELOPMENT) console.error(error);
                notify({
                    level: "error",
                    title: "Failed to Update Settings",
                    message: "",
                });
            });
    };

    if (!user || !user.uid) return null;

    return (
        <div style={{ margin: "10px" }}>
            <div>
                <Typography variant={"h4"} component={"h4"}>
                    Notification Frequency
                </Typography>
            </div>
            <div
                style={{
                    display: "flex",
                    flexDirection: "row",
                    justifyContent: "flex-start",
                }}
            >
                <div style={{ textAlign: "center", margin: "20px" }}>
                    <Typography
                        variant={"body1"}
                        component={"p"}
                        onClick={setDaily}
                    >
                        Daily
                    </Typography>
                    <Checkbox
                        checked={
                            notificationFrequency ===
                            NOTIFICATION_FREQUENCY.Daily
                        }
                        onChange={setDaily}
                    />
                </div>
                <div style={{ textAlign: "center", margin: "20px" }}>
                    <Typography
                        variant={"body1"}
                        component={"p"}
                        onClick={setWeekly}
                    >
                        Weekly/Once
                    </Typography>
                    <Checkbox
                        checked={
                            notificationFrequency ===
                            NOTIFICATION_FREQUENCY.Weekly
                        }
                        onChange={setWeekly}
                    />
                </div>
                <div style={{ textAlign: "center", margin: "20px" }}>
                    <Typography
                        variant={"body1"}
                        component={"p"}
                        onClick={setOff}
                    >
                        Off
                    </Typography>
                    <Checkbox
                        checked={
                            notificationFrequency === NOTIFICATION_FREQUENCY.Off
                        }
                        onChange={setOff}
                    />
                </div>
            </div>
            <div>
                <Typography variant={"h4"} component={"h4"}>
                    Notification Type
                </Typography>
            </div>
            <div
                style={{
                    display: "flex",
                    flexDirection: "row",
                    justifyContent: "flex-start",
                }}
            >
                <div style={{ textAlign: "center", margin: "20px" }}>
                    <Typography
                        variant={"body1"}
                        component={"p"}
                        onClick={setEmail}
                    >
                        Email
                    </Typography>
                    <Checkbox
                        checked={notificationType === NOTIFICATION_TYPE.Email}
                        onChange={setEmail}
                        disabled={
                            notificationFrequency === NOTIFICATION_FREQUENCY.Off
                        }
                    />
                </div>
            </div>

            <Button
                style={{ margin: "5% auto" }}
                onClick={handleSubmit}
                variant="contained"
                color="primary"
                size="large"
                startIcon={<Save />}
            >
                Save
            </Button>
        </div>
    );
};

export default UserSettings;
