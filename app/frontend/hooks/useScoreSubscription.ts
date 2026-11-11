import { router } from "@inertiajs/react";
import consumer from "app/frontend/channels/consumer";
import { useEffect, useState } from "react";
import { logDev } from "app/frontend/sway_utils";

// @lat: [[system-shape#Keeping scores fresh]]
export const useScoreSubscription = (onlyProps: string[], enabled = true) => {
    // @lat: [[score-subscription-initialized-event-bug#Why useScoreSubscription has no isSubscribed flag]]
    const [isAwaitingScoreUpdate, setIsAwaitingScoreUpdate] = useState<boolean>(false);
    useEffect(() => {
        if (!enabled) return;
        const subscription = consumer.subscriptions.create("ScoreChannel", {
            received(data: { action: string }) {
                if (data.action === "refresh_scores") {
                    setIsAwaitingScoreUpdate(true);
                    logDev("useScoreSubscription - refresh_scores signal received, reloading props:", onlyProps);
                    router.reload({
                        only: onlyProps,
                        onFinish: () => setIsAwaitingScoreUpdate(false),
                    });
                }
            },
        });

        return () => {
            subscription.unsubscribe();
        };
    }, [enabled, onlyProps]);
    return isAwaitingScoreUpdate;
};
