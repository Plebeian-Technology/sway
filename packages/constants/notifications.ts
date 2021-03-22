import { sway } from "sway";

export const NOTIFICATION_FREQUENCY: {
    Daily: sway.TNotificationFrequency;
    Weekly: sway.TNotificationFrequency;
    Off: sway.TNotificationFrequency;
} = {
    Daily: 0,
    Weekly: 1,
    Off: 2,
};
export const NOTIFICATION_TYPE: {
    Email: sway.TNotificationType;
    Sms: sway.TNotificationType;
    EmailSms: sway.TNotificationType;
    None: sway.TNotificationType;
} = {
    Email: 0,
    Sms: 1,
    EmailSms: 2,
    None: 3,
};