// @lat: [[mobile-sync-hooks#useScoreSubscription]]
import { useEffect, useState } from "react";

import { tokenStore } from "../auth/tokenStore";
import { getConsumer } from "../channels/consumer";

interface ScoreChannelMessage {
    action: string;
}

interface CableSubscription {
    unsubscribe(): void;
}

export function useScoreSubscription(onRefresh: () => void): { isSubscribed: boolean } {
    const [isSubscribed, setIsSubscribed] = useState(false);

    useEffect(() => {
        let active = true;
        let subscription: CableSubscription | undefined;

        (async () => {
            const token = await tokenStore.get();
            const consumer = await getConsumer(token);
            if (!active) return;

            subscription = consumer.subscriptions.create("ScoreChannel", {
                initialize() {
                    setIsSubscribed(true);
                },
                received(data: ScoreChannelMessage) {
                    if (data.action === "refresh_scores") {
                        setIsSubscribed(false);
                        onRefresh();
                        setIsSubscribed(true);
                    }
                },
            }) as CableSubscription;
        })();

        return () => {
            active = false;
            try {
                subscription?.unsubscribe();
            } catch {}
        };
    }, [onRefresh]);

    return { isSubscribed };
}
