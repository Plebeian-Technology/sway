/** @format */

import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "app/frontend/sway_constants";
import { IS_DEVELOPMENT } from "app/frontend/sway_utils";
import { omit } from "lodash";
import { useState } from "react";
import { Button } from "react-bootstrap";
import { FiSave } from "react-icons/fi";

import { useDispatch } from "react-redux";
import { sway } from "sway";
import { NON_SERIALIZEABLE_FIREBASE_FIELDS } from "../../../sway_constants/users";
import { useUserWithSettingsAdmin } from "../../../hooks/users/useUserWithSettingsAdmin";
import { setUser } from "../../../redux/actions/userActions";
import { notify, swayFireClient } from "../../../sway_utils";
import UserNotificationSettings from "./UserNotificationSettings";

const UserSettings: React.FC = () => {
    const dispatch = useDispatch();
    const { user, settings, isAdmin } = useUserWithSettingsAdmin();

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
    const [notificationType, setNotificationType] = useState<sway.TNotificationType>(defaultType);

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
                    setUser(
                        omit(
                            {
                                user,
                                settings: {
                                    ...settings,
                                    notificationFrequency,
                                    notificationType,
                                },
                                isAdmin,
                            },
                            NON_SERIALIZEABLE_FIREBASE_FIELDS,
                        ),
                    ),
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
        <div>
            <UserNotificationSettings
                notificationFrequency={notificationFrequency}
                setNotificationFrequency={setNotificationFrequency}
                notificationType={notificationType}
                setNotificationType={setNotificationType}
            />
            <Button onClick={handleSubmit} size="lg">
                <FiSave />
                &nbsp;Save
            </Button>
        </div>
    );
};

export default UserSettings;
