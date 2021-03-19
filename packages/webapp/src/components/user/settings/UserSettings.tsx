/** @format */

import { Button } from "@material-ui/core";
import { Save } from "@material-ui/icons";
import { IS_DEVELOPMENT } from "@sway/utils";
import React, { useState } from "react";
import { sway } from "sway";
import { notify, swayFireClient } from "../../../utils";
import UserCongratulationsSettings from "./UserCongratulationsSettings";
import UserNotificationSettings from "./UserNotificationSettings";

interface IProps {
    userWithSettings: sway.IUserWithSettings | undefined;
}

const UserSettings: React.FC<IProps> = ({ userWithSettings }) => {
    const user = userWithSettings?.user;
    const settings = userWithSettings?.settings;

    const defaultFrequency =
        typeof settings?.notificationFrequency === "number"
            ? settings?.notificationFrequency
            : null;
    const defaultType =
        typeof settings?.notificationType === "number"
            ? settings?.notificationType
            : null;

    const [
        notificationFrequency,
        setNotificationFrequency,
    ] = useState<sway.TNotificationFrequency | null>(defaultFrequency);
    const [
        notificationType,
        setNotificationType,
    ] = useState<sway.TNotificationType | null>(defaultType);

    const congratulationSettings = settings?.congratulations;

    const [
        congratulationTypes,
        setCongratulationsTypes,
    ] = useState<sway.ICongratulationsSettings>({
        isCongratulateOnUserVote: Boolean(
            congratulationSettings?.isCongratulateOnUserVote,
        ),
        isCongratulateOnInviteSent: Boolean(
            congratulationSettings?.isCongratulateOnInviteSent,
        ),
        isCongratulateOnSocialShare: Boolean(
            congratulationSettings?.isCongratulateOnSocialShare,
        ),
    });

    const handleSubmit = async () => {
        if (!user?.uid || user.isAnonymous || !settings) return;

        const values = {
            notificationFrequency,
            notificationType,
            congratulations: {
                ...congratulationTypes,
            },
        } as sway.IUserSettings;

        swayFireClient()
            .userSettings(user?.uid)
            .update({
                ...settings,
                ...values,
            })
            .then(() => {
                notify({
                    level: "success",
                    message: "Updated Settings",
                });
            })
            .catch((error: Error) => {
                if (IS_DEVELOPMENT) console.error(error);
                notify({
                    level: "error",
                    message: "Failed to Update Settings",
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
            <UserCongratulationsSettings
                congratulationTypes={congratulationTypes}
                setCongratulationsTypes={setCongratulationsTypes}
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
