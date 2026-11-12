import { router } from "@inertiajs/react";
import consumer from "app/frontend/channels/consumer";
import { useEffect } from "react";

const NEWEST_KEYS_ONLY = ["newest_keys"];

// @lat: [[home-feed#Live feed updates]]
export const useFeedSubscription = (enabled = true) => {
    useEffect(() => {
        if (!enabled) return;
        const subscription = consumer.subscriptions.create("FeedChannel", {
            received(data: { type?: string }) {
                if (data.type === "feed_updated") {
                    router.reload({
                        only: NEWEST_KEYS_ONLY,
                    });
                }
            },
        });

        return () => {
            subscription.unsubscribe();
        };
    }, [enabled]);
};
