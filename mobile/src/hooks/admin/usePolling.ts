// @lat: [[mobile-bill-creator#Sections#The pipeline progress section#Polling while a run is in flight]]
import { useCallback } from "react";
import { useFocusEffect } from "@react-navigation/native";

export function usePolling(refresh: () => void | Promise<void>, active: boolean, intervalMs: number): void {
    useFocusEffect(
        useCallback(() => {
            if (!active) return undefined;
            const interval = setInterval(() => {
                void refresh();
            }, intervalMs);
            return () => clearInterval(interval);
        }, [refresh, active, intervalMs]),
    );
}
