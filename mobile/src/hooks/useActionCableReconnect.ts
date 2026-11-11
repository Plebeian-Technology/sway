// @lat: [[mobile-sync-hooks#useActionCableReconnect]]
import { useEffect, useRef } from "react";
import { addEventListener as addNetInfoListener } from "@react-native-community/netinfo";

export function useActionCableReconnect(onReconnect: () => void): void {
    const wasOffline = useRef(false);

    useEffect(() => {
        const unsubscribe = addNetInfoListener((state) => {
            const online = !!state.isConnected;
            if (online && wasOffline.current) {
                onReconnect();
            }
            wasOffline.current = !online;
        });
        return () => {
            unsubscribe();
        };
    }, [onReconnect]);
}
