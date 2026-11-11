// @lat: [[mobile-sync-hooks#useFocusedSync]]
import { useCallback, useRef } from "react";
import { useFocusEffect } from "@react-navigation/native";
import { addEventListener as addNetInfoListener } from "@react-native-community/netinfo";

import { tokenStore } from "../auth/tokenStore";
import { getConsumer } from "../channels/consumer";

interface CableSubscription {
    unsubscribe(): void;
}
interface ScoreChannelMessage {
    action: string;
}

interface UseFocusedSyncOptions {
    refresh: () => void;
    // milliseconds
    pollMs?: number;
    channel?: string;
}

export function useFocusedSync({ refresh, pollMs = 15000, channel = "ScoreChannel" }: UseFocusedSyncOptions): void {
    const wasOfflineRef = useRef<boolean>(false);

    useFocusEffect(
        useCallback(() => {
            let cancelled = false;
            let subscription: CableSubscription | undefined;
            let netInfoUnsub: (() => void) | undefined;

            const interval = setInterval(refresh, pollMs);

            (async () => {
                const token = await tokenStore.get();
                const consumer = await getConsumer(token);
                if (cancelled) return;
                subscription = consumer.subscriptions.create(channel, {
                    received(data: ScoreChannelMessage) {
                        if (data.action === "refresh_scores") {
                            refresh();
                        }
                    },
                }) as CableSubscription;
            })();

            netInfoUnsub = addNetInfoListener((state) => {
                const online = !!state.isConnected;
                if (online && wasOfflineRef.current) refresh();
                wasOfflineRef.current = !online;
            });

            return () => {
                cancelled = true;
                clearInterval(interval);
                try {
                    subscription?.unsubscribe();
                } catch {}
                netInfoUnsub?.();
            };
        }, [refresh, pollMs, channel]),
    );
}
