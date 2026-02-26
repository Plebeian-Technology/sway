import { router } from "@inertiajs/react";
import consumer from "app/frontend/channels/consumer";
import { useEffect } from "react";
import { logDev } from "../sway_utils";

export const useScoreSubscription = (onlyProps: string[]) => {
    useEffect(() => {
        const subscription = consumer.subscriptions.create("ScoreChannel", {
            received(data: { action: string }) {
                if (data.action === "refresh_scores") {
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
};
