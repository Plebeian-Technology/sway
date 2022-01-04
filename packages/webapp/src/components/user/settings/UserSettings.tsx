/** @format */

import { Button } from "@mui/material";
import { Save } from "@mui/icons-material";
import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "@sway/constants";
import { IS_DEVELOPMENT } from "@sway/utils";
import React, { useState } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";
import { setUser } from "../../../redux/actions/userActions";
import { notify, swayFireClient } from "../../../utils";
import UserNotificationSettings from "./UserNotificationSettings";

interface IProps {
    userWithSettingsAdmin: sway.IUserWithSettingsAdmin | undefined;
}

const UserSettings: React.FC<IProps> = ({ userWithSettingsAdmin }) => {
    const dispatch = useDispatch();
    const user = userWithSettingsAdmin?.user;
    const settings = userWithSettingsAdmin?.settings;

    const defaultFrequency =
        typeof settings?.notificationFrequency === "number"
            ? settings?.notificationFrequency
            : NOTIFICATION_FREQUENCY.Daily;
    const defaultType =
        typeof settings?.notificationType === "number"
            ? settings?.notificationType
            : NOTIFICATION_TYPE.EmailSms;

    const [notificationFrequency, setNotificationFrequency] =
        useState<sway.TNotificationFrequency>(defaultFrequency);
    const [notificationType, setNotificationType] =
        useState<sway.TNotificationType>(defaultType);

    const handleSubmit = async () => {
        if (!user?.uid || user.isAnonymous || !settings) return;

        if (notificationType === null || notificationFrequency === null) {
            console.error(
                "error updating user settings, notification frequency or type was null -",
                {
                    notificationFrequency,
                    notificationType,
                },
            );
            notify({
                level: "error",
                title: "Could not update settings.",
                message: "Please try selecting different settings.",
            });
            return;
        }

        swayFireClient()
            .userSettings(user?.uid)
            .update({
                notificationFrequency,
                notificationType,
            } as sway.IUserSettings)
            .then(() => {
                dispatch(
                    setUser({
                        user: user,
                        settings: {
                            ...settings,
                            notificationFrequency,
                            notificationType,
                        },
                        isAdmin: userWithSettingsAdmin.isAdmin,
                    }),
                );
                notify({
                    level: "success",
                    title: "Updated Settings",
                });
            })
            .catch((error: Error) => {
                if (IS_DEVELOPMENT) console.error(error);
                notify({
                    level: "error",
                    title: "Failed to Update Settings",
                });
            });
    };

    if (!user || !user.uid) return null;

    return (
        <div style={{ margin: "10px" }}>
            <UserNotificationSettings
                notificationFrequency={notificationFrequency}
                setNotificationFrequency={setNotificationFrequency}
                notificationType={notificationType}
                setNotificationType={setNotificationType}
            />
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
