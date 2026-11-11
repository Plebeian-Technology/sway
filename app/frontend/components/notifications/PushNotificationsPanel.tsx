import { Deferred } from "@inertiajs/react";
import { useMemo } from "react";
import { BellOff, BellRing, Send } from "lucide-react";
import { sway } from "sway";

import { usePushSubscription } from "app/frontend/hooks/notifications/usePushSubscription";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Separator } from "app/frontend/components/ui/separator";

interface IProps {
    subscriptions: sway.notifications.IPushNotificationSubscription[];
}

const PushSubscriptionsSkeleton = () => (
    <div className="space-y-2" aria-busy="true" aria-live="polite">
        <div className="h-4 w-40 animate-pulse rounded bg-muted" />
        <div className="h-12 w-full animate-pulse rounded-xl bg-muted" />
        <div className="h-12 w-full animate-pulse rounded-xl bg-muted" />
    </div>
);

interface ISubscriptionsListProps {
    subscriptions: sway.notifications.IPushNotificationSubscription[];
    currentEndpoint: string | undefined;
}

const PushSubscriptionsList: React.FC<ISubscriptionsListProps> = ({ subscriptions, currentEndpoint }) => {
    const others = useMemo(
        () => (subscriptions || []).filter((s) => s.subscribed && s.endpoint !== currentEndpoint),
        [subscriptions, currentEndpoint],
    );

    if (!subscriptions || subscriptions.length === 0) {
        return <p className="text-sm text-muted-foreground italic">No push devices are currently registered to you.</p>;
    }

    return (
        <div className="space-y-2">
            <div className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
                Other devices currently enabled
            </div>
            <div className="text-sm font-semibold tabular-nums lining-nums">{others.length}</div>
        </div>
    );
};

const PushNotificationsPanel: React.FC<IProps> = ({ subscriptions }) => {
    const { support, isEnabledHere, currentEndpoint, register, test, disable, processing } =
        usePushSubscription(subscriptions);

    if (support === "unsupported") {
        return (
            <Card data-testid="notification-push-toggle">
                <CardHeader>
                    <div className="flex items-start justify-between gap-4">
                        <CardTitle className="text-lg">Push notifications on this device</CardTitle>
                        <Badge variant="stamp" tone="warning">
                            Unsupported
                        </Badge>
                    </div>
                </CardHeader>
                <CardContent>
                    <Alert variant="warning">
                        <BellOff />
                        <AlertTitle>Push notifications are not available</AlertTitle>
                        <AlertDescription>
                            Your current browser or tab does not support the Push API. Private / incognito tabs and some
                            mobile browsers disable it. Try again from a regular browser window.
                        </AlertDescription>
                    </Alert>
                </CardContent>
            </Card>
        );
    }

    return (
        <Card data-testid="notification-push-toggle" aria-live="polite">
            <CardHeader>
                <div className="flex items-start justify-between gap-4">
                    <CardTitle className="text-lg">Push notifications on this device</CardTitle>
                    <Badge variant="stamp" tone={isEnabledHere ? "success" : "neutral"}>
                        {isEnabledHere ? "Enabled" : "Disabled"}
                    </Badge>
                </div>
            </CardHeader>
            <CardContent className="space-y-4 md:text-left">
                {isEnabledHere ? (
                    <>
                        <p className="text-sm text-muted-foreground">
                            We'll stop sending push notifications to this device as soon as you disable them. If you
                            don't receive a test notification, make sure notifications are permitted for this browser in
                            your device settings.
                        </p>
                        <div className="flex flex-wrap gap-2 justify-center md:justify-start">
                            <Button type="button" variant="destructive" onClick={disable} disabled={processing.disable}>
                                <BellOff /> Disable on this device
                            </Button>
                            <Button type="button" variant="outline" onClick={test} disabled={processing.test}>
                                <Send /> Send test notification
                            </Button>
                        </div>
                    </>
                ) : (
                    <>
                        <p className="text-sm text-muted-foreground">
                            We'll send you a push notification whenever a new Bill of the Month is released.
                        </p>
                        <div className="flex justify-center md:justify-start">
                            <Button
                                type="button"
                                variant="default"
                                size="lg"
                                onClick={register}
                                disabled={processing.register}
                                className="h-auto min-h-10 max-w-full py-2 whitespace-normal"
                            >
                                <BellRing /> Enable push notifications on this device
                            </Button>
                        </div>
                    </>
                )}

                <Separator />

                <Deferred data="subscriptions" fallback={<PushSubscriptionsSkeleton />}>
                    <PushSubscriptionsList subscriptions={subscriptions || []} currentEndpoint={currentEndpoint} />
                </Deferred>
            </CardContent>
        </Card>
    );
};

export default PushNotificationsPanel;
