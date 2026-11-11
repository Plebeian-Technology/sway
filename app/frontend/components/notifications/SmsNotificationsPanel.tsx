import { useForm } from "@inertiajs/react";
import { sway } from "sway";

import SmsNotificationsPanelView from "app/frontend/components/notifications/SmsNotificationsPanelView";

interface IProps {
    user: Pick<sway.IUser, "sms_notifications_enabled">;
    sms_phone: string | null;
}

const SmsNotificationsPanel: React.FC<IProps> = ({ user, sms_phone }) => {
    const { data, setData, patch, processing } = useForm({
        user: {
            sms_notifications_enabled: Boolean(user.sms_notifications_enabled),
        },
    });

    const isDirty = data.user.sms_notifications_enabled !== Boolean(user.sms_notifications_enabled);

    const submit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        patch("/notifications/settings", {
            preserveScroll: true,
        });
    };

    return (
        <SmsNotificationsPanelView
            enabled={data.user.sms_notifications_enabled}
            sms_phone={sms_phone}
            canSubmit={!processing && isDirty}
            onEnabledChange={(checked) =>
                setData("user", {
                    ...data.user,
                    sms_notifications_enabled: checked,
                })
            }
            onSubmit={submit}
        />
    );
};

export default SmsNotificationsPanel;
