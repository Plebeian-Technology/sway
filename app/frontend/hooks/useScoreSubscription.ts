import { router } from "@inertiajs/react";
import consumer from "app/frontend/channels/consumer";
import { useEffect, useState } from "react";
import { logDev } from "../sway_utils";

export const useScoreSubscription = (onlyProps: string[]) => {
    const [isSubscribed, setIsSubscribed] = useState<boolean>(false);
    useEffect(() => {
        const subscription = consumer.subscriptions.create("ScoreChannel", {
            initialize() {
                setIsSubscribed(true);
            },
            received(data: { action: string }) {
                if (data.action === "refresh_scores") {
                    setIsSubscribed(false);
                    logDev("useScoreSubscription - refresh_scores signal received, reloading props:", onlyProps);
                    router.reload({
                        only: onlyProps,
                    });
                }
            },
        });

        return () => {
            subscription.unsubscribe();
        };
    }, [onlyProps]);
    return isSubscribed;
};
