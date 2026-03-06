import { Box, Tab, Tabs } from "@mui/material";
import PhoneSmsNotifications from "app/frontend/pages/notifications/PhoneSmsNotifications";
import { useState } from "react";
import { sway } from "sway";

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

const Notifications: React.FC<IProps> = ({ user }) => {
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
                <PhoneSmsNotifications user={user} />
            </CustomTabPanel>
        </Box>
    );
};

export default Notifications;
