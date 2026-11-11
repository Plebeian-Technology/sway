// @lat: [[mobile-freshness-hook#useFreshness hook]]
import { useEffect, useState } from "react";
import { openDatabase } from "../cache/db";

export interface FreshnessState {
    lastSynced: Date | null;
    isRevalidating: boolean;
}

export type FreshnessTable = "bills" | "user_votes" | "legislators" | "bootstrap_cache";

export const useFreshness = (table: FreshnessTable, isRevalidating = false): FreshnessState => {
    const [lastSynced, setLastSynced] = useState<Date | null>(null);

    useEffect(() => {
        let cancelled = false;
        const probe = async () => {
            try {
                const d = await openDatabase();
                const col = table === "bootstrap_cache" ? "fetched_at" : "cached_at";
                const row = await d.getFirstAsync<{ ts: number | null }>(`SELECT MAX(${col}) AS ts FROM ${table}`);
                if (!cancelled && row && typeof row.ts === "number") {
                    setLastSynced(new Date(row.ts));
                }
            } catch {}
        };
        probe();
        return () => {
            cancelled = true;
        };
    }, [table, isRevalidating]);

    return { lastSynced, isRevalidating };
};
