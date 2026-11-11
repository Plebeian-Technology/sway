// @lat: [[mobile-sqlite-cache-design#Why legislatorCache caps rows per locale]]
import { openDatabase } from "./db";

export interface CachedLegislator {
    legislator: Record<string, unknown>;
    cachedAt: number;
}

const MAX_CACHED_LEGISLATORS_PER_SWAY_LOCALE = 50;

export async function get(swayLocaleId: number): Promise<CachedLegislator[]> {
    const d = await openDatabase();
    const rows = await d.getAllAsync<{ data: string; cached_at: number }>(
        `SELECT data, cached_at FROM legislators WHERE locale_id = ? ORDER BY cached_at DESC LIMIT ${MAX_CACHED_LEGISLATORS_PER_SWAY_LOCALE}`,
        [swayLocaleId],
    );
    return rows.map((r) => ({
        legislator: JSON.parse(r.data) as Record<string, unknown>,
        cachedAt: r.cached_at,
    }));
}

export async function set(swayLocaleId: number, legs: ({ id: number } & Record<string, unknown>)[]): Promise<void> {
    const d = await openDatabase();
    await d.withTransactionAsync(async () => {
        await d.runAsync("DELETE FROM legislators WHERE locale_id = ?", [swayLocaleId]);
        const now = Date.now();
        for (const l of legs.slice(0, MAX_CACHED_LEGISLATORS_PER_SWAY_LOCALE)) {
            await d.runAsync(
                "INSERT OR REPLACE INTO legislators (id, locale_id, data, cached_at) VALUES (?, ?, ?, ?)",
                [l.id, swayLocaleId, JSON.stringify(l), now],
            );
        }
    });
}

export async function clear(): Promise<void> {
    const d = await openDatabase();
    await d.runAsync("DELETE FROM legislators");
}
