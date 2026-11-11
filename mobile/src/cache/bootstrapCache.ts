// @lat: [[mobile-bootstrap-lifecycle#Where bootstrap data is stored, and why]]
import { openDatabase } from "./db";

export interface CachedBootstrap<T = unknown> {
    payload: T;
    fetchedAt: Date;
}

interface Row {
    payload_json: string;
    fetched_at: number;
}

export const bootstrapCache = {
    async get<T = unknown>(userId: string): Promise<CachedBootstrap<T> | null> {
        const d = await openDatabase();
        const row = await d.getFirstAsync<Row>(
            "SELECT payload_json, fetched_at FROM bootstrap_cache WHERE user_id = ?",
            [userId],
        );
        if (!row) return null;
        try {
            const payload = JSON.parse(row.payload_json) as T;
            return { payload, fetchedAt: new Date(row.fetched_at) };
        } catch {
            return null;
        }
    },

    async set(userId: string, payload: unknown): Promise<void> {
        const d = await openDatabase();
        await d.runAsync(
            "INSERT OR REPLACE INTO bootstrap_cache (user_id, payload_json, fetched_at) VALUES (?, ?, ?)",
            [userId, JSON.stringify(payload), Date.now()],
        );
    },

    async purge(): Promise<void> {
        const d = await openDatabase();
        await d.runAsync("DELETE FROM bootstrap_cache");
    },
};
