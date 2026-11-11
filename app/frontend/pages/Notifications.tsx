// @lat: [[notifications-tab-url#The Notifications tab in the URL]]

import { useCallback, useMemo, useReducer } from "react";
import { sway } from "sway";

import OrganizationsNotificationsPanel from "app/frontend/components/notifications/OrganizationsNotificationsPanel";
import PushNotificationsPanel from "app/frontend/components/notifications/PushNotificationsPanel";
import SmsNotificationsPanel from "app/frontend/components/notifications/SmsNotificationsPanel";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "app/frontend/components/ui/tabs";
import { detectSupport } from "app/frontend/hooks/notifications/usePushSubscription";

interface IProps {
    user: sway.IUser;
    sway_locale: sway.ISwayLocale;
    subscriptions: sway.notifications.IPushNotificationSubscription[];
    sms_notifications_enabled?: boolean;
    sms_phone: string | null;
    org_position_taken?: boolean;
    org_position_cadence_default?: string;
    notify_on_new_position_default?: boolean;
    notify_on_support_change_default?: boolean;
    notify_on_summary_change_default?: boolean;
}

type TabValue = "push" | "sms" | "organizations";

const isTabValue = (v: string | null | undefined): v is TabValue =>
    v === "push" || v === "sms" || v === "organizations";

const readTabFromUrl = (): TabValue | undefined => {
    if (typeof window === "undefined") return undefined;
    const params = new URLSearchParams(window.location.search);
    const notificationsTab = params.get("notifications_tab");
    if (params.has("notifications_tab")) {
        return isTabValue(notificationsTab) ? notificationsTab : undefined;
    }

    const legacyTab = params.get("tab");
    return isTabValue(legacyTab) ? legacyTab : undefined;
};

const Notifications: React.FC<IProps> = ({
    user,
    subscriptions,
    sms_phone,
    org_position_taken,
    org_position_cadence_default,
    notify_on_new_position_default,
    notify_on_support_change_default,
    notify_on_summary_change_default,
}) => {
    // @lat: [[notifications-tab-url#Why the open tab is recomputed on every render instead of held in state]]
    const pushSupported = useMemo(() => detectSupport() === "supported", []);

    // @lat: [[notifications-tab-url#What the in-place rewrite gives up]]
    const [, tabDidChange] = useReducer((count: number) => count + 1, 0);

    const tab: TabValue = readTabFromUrl() ?? (pushSupported ? "push" : "sms");

    const handleTabChange = useCallback((value: string) => {
        if (!isTabValue(value)) return;

        if (typeof window !== "undefined") {
            const url = new URL(window.location.href);
            url.searchParams.set("notifications_tab", value);
            url.searchParams.delete("tab");
            window.history.replaceState(window.history.state, "", url.pathname + url.search);
            tabDidChange();
        }
    }, []);

    return (
        <div className="mx-auto w-full max-w-2xl space-y-6">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">Notifications</h1>
                <p className="text-sm text-muted-foreground">
                    Choose how Sway reaches you when a new Bill of the Month is released.
                </p>
            </div>

            <Tabs value={tab} onValueChange={handleTabChange} className="gap-6">
                <TabsList>
                    <TabsTrigger value="push">Push</TabsTrigger>
                    <TabsTrigger value="sms">SMS</TabsTrigger>
                    <TabsTrigger value="organizations">Organizations</TabsTrigger>
                </TabsList>

                <TabsContent value="push">
                    <PushNotificationsPanel subscriptions={subscriptions} />
                </TabsContent>

                <TabsContent value="sms">
                    <SmsNotificationsPanel user={user} sms_phone={sms_phone} />
                </TabsContent>

                <TabsContent value="organizations">
                    <OrganizationsNotificationsPanel
                        org_position_taken={org_position_taken}
                        org_position_cadence_default={org_position_cadence_default}
                        notify_on_new_position_default={notify_on_new_position_default}
                        notify_on_support_change_default={notify_on_support_change_default}
                        notify_on_summary_change_default={notify_on_summary_change_default}
                    />
                </TabsContent>
            </Tabs>
        </div>
    );
};

export default Notifications;
