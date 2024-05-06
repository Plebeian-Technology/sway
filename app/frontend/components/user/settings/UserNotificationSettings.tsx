/** @format */

import { NOTIFICATION_FREQUENCY, NOTIFICATION_TYPE } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";

import { sway } from "sway";
import SwayCheckbox from "../../shared/SwayCheckbox";

interface IProps {
    notificationFrequency: sway.TNotificationFrequency;
    setNotificationFrequency: (frequency: sway.TNotificationFrequency) => void;
    notificationType: sway.TNotificationType;
    setNotificationType: (type: sway.TNotificationType) => void;
}

const UserNotificationSettings: React.FC<IProps> = ({
    notificationFrequency,
    setNotificationFrequency,
    notificationType,
    setNotificationType,
}) => {
    const setDaily = () => setNotificationFrequency(NOTIFICATION_FREQUENCY.Daily);
    const setWeekly = () => setNotificationFrequency(NOTIFICATION_FREQUENCY.Weekly);
    const setOff = () => {
        setNotificationFrequency(NOTIFICATION_FREQUENCY.Off);
        setNotificationType(NOTIFICATION_TYPE.None);
    };

    const setType = (e: React.ChangeEvent<HTMLInputElement>) => {
        const { name } = e.target;
        switch (name) {
            case typeNames[NOTIFICATION_TYPE.Email]: {
                setNotificationType(NOTIFICATION_TYPE.Email);
                break;
            }
            case typeNames[NOTIFICATION_TYPE.EmailSms]: {
                setNotificationType(NOTIFICATION_TYPE.EmailSms);
                break;
            }
            case typeNames[NOTIFICATION_TYPE.Sms]: {
                setNotificationType(NOTIFICATION_TYPE.Sms);
                break;
            }
            case typeNames[NOTIFICATION_TYPE.None]: {
                setNotificationFrequency(NOTIFICATION_FREQUENCY.Off);
                setNotificationType(NOTIFICATION_TYPE.None);
                break;
            }
            default: {
                logDev(
                    `received name - ${name} - for notification type which is not expected. setting default`,
                );
                setNotificationType(NOTIFICATION_TYPE.EmailSms);
                break;
            }
        }
    };

    const typeNames = {
        [NOTIFICATION_TYPE.Email]: "email",
        [NOTIFICATION_TYPE.EmailSms]: "emailsms",
        [NOTIFICATION_TYPE.Sms]: "sms",
        [NOTIFICATION_TYPE.None]: "none",
    };

    return (
        <div>
            <div>
                <h4>Notification Frequency</h4>
                <p>
                    You will not be sent a notification after you have voted on a new Bill of the
                    Week.
                </p>
            </div>
            <div>
                <div>
                    <SwayCheckbox
                        name={"daily"}
                        id={"daily"}
                        label={"Daily"}
                        checked={notificationFrequency === NOTIFICATION_FREQUENCY.Daily}
                        onChange={setDaily}
                        disabled={false}
                    />
                </div>
                <div>
                    <SwayCheckbox
                        name={"weekly"}
                        id={"weekly"}
                        label={"Weekly/Once"}
                        checked={notificationFrequency === NOTIFICATION_FREQUENCY.Weekly}
                        onChange={setWeekly}
                        disabled={false}
                    />
                </div>
                <div>
                    <SwayCheckbox
                        name={"off"}
                        id={"off"}
                        label={"Off"}
                        checked={notificationFrequency === NOTIFICATION_FREQUENCY.Off}
                        onChange={setOff}
                        disabled={false}
                    />
                </div>
            </div>
            <div>
                <h4>Notification Type</h4>
            </div>
            <div>
                <div>
                    <SwayCheckbox
                        name={typeNames[NOTIFICATION_TYPE.Email]}
                        id={"email"}
                        label={"Email"}
                        checked={notificationType === NOTIFICATION_TYPE.Email}
                        onChange={setType}
                        disabled={notificationFrequency === NOTIFICATION_FREQUENCY.Off}
                    />
                </div>
                <div>
                    <SwayCheckbox
                        name={typeNames[NOTIFICATION_TYPE.EmailSms]}
                        id={"emailsms"}
                        label={"Email and SMS/Text Message (SMS only sent once per week)"}
                        checked={notificationType === NOTIFICATION_TYPE.EmailSms}
                        onChange={setType}
                        disabled={notificationFrequency === NOTIFICATION_FREQUENCY.Off}
                    />
                </div>
                <div>
                    <SwayCheckbox
                        name={typeNames[NOTIFICATION_TYPE.Sms]}
                        id={"sms"}
                        label={"SMS/Text Message (only sent once per week)"}
                        checked={notificationType === NOTIFICATION_TYPE.Sms}
                        onChange={setType}
                        disabled={notificationFrequency === NOTIFICATION_FREQUENCY.Off}
                    />
                </div>
                <div>
                    <SwayCheckbox
                        name={typeNames[NOTIFICATION_TYPE.None]}
                        id={"none"}
                        label={"None"}
                        checked={notificationType === NOTIFICATION_TYPE.None}
                        onChange={setType}
                        disabled={notificationFrequency === NOTIFICATION_FREQUENCY.Off}
                    />
                </div>
            </div>
        </div>
    );
};

export default UserNotificationSettings;
