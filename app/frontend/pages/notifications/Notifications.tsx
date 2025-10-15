import WebPushNotifications from "app/frontend/pages/notifications/WebPushNotifications";
import { useState } from "react";
import { Tabs, Tab, Box } from "@mui/material";
import { sway } from "sway";
import PhoneSmsNotifications from "app/frontend/pages/notifications/PhoneSmsNotifications";

interface IProps {
    user: sway.IUser;
    sway_locale: sway.ISwayLocale;
    subscriptions: sway.notifications.IPushNotificationSubscription[];
}

enum NotificationType {
    PHONE = "phone",
    WEB_PUSH = "webpush",
}

interface TabPanelProps {
    children?: React.ReactNode;
    index: NotificationType;
    value: NotificationType;
}

function CustomTabPanel(props: TabPanelProps) {
    const { children, value, index, ...other } = props;

    return (
        <div
            role="tabpanel"
            hidden={value !== index}
            id={`simple-tabpanel-${index}`}
            aria-labelledby={`simple-tab-${index}`}
            {...other}
        >
            {value === index && <Box sx={{ p: 3 }}>{children}</Box>}
        </div>
    );
}

const Notifications: React.FC<IProps> = () => {
    const [value, setValue] = useState<NotificationType>(NotificationType.PHONE);

    const handleChange = (_event: React.SyntheticEvent, newValue: string) => {
        setValue(newValue as NotificationType);
    };

    return (
        <Box sx={{ width: "100%" }}>
            <Tabs
                value={value}
                onChange={handleChange}
                textColor="secondary"
                indicatorColor="secondary"
                aria-label="Notification Type Tabs"
                centered
            >
                <Tab value={NotificationType.PHONE} label="Text Message Notifications" />
                <Tab value={NotificationType.WEB_PUSH} label="Push Notifications" />
            </Tabs>
            <CustomTabPanel value={value} index={NotificationType.PHONE}>
                <PhoneSmsNotifications />
            </CustomTabPanel>
            <CustomTabPanel value={value} index={NotificationType.WEB_PUSH}>
                <WebPushNotifications />
            </CustomTabPanel>
        </Box>
    );
};

export default Notifications;
