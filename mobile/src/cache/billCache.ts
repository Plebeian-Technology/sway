// @lat: [[mobile-sqlite-cache-design#Why billCache caps rows per locale in a transaction]]
import { openDatabase } from "./db";

export interface CachedBill {
    bill: Record<string, unknown>;
    cachedAt: number;
}

const MAX_CACHED_BILLS_PER_SWAY_LOCALE = 24;

export async function get(swayLocaleId: number): Promise<CachedBill[]> {
    const d = await openDatabase();
    const rows = await d.getAllAsync<{ data: string; cached_at: number }>(
        `SELECT data, cached_at FROM bills WHERE locale_id = ? ORDER BY cached_at DESC LIMIT ${MAX_CACHED_BILLS_PER_SWAY_LOCALE}`,
        [swayLocaleId],
    );
    return rows.map((r) => ({ bill: JSON.parse(r.data) as Record<string, unknown>, cachedAt: r.cached_at }));
}

export async function set(swayLocaleId: number, bills: ({ id: number } & Record<string, unknown>)[]): Promise<void> {
    const d = await openDatabase();
    await d.withTransactionAsync(async () => {
        await d.runAsync("DELETE FROM bills WHERE locale_id = ?", [swayLocaleId]);
        const now = Date.now();
        for (const b of bills.slice(0, MAX_CACHED_BILLS_PER_SWAY_LOCALE)) {
            await d.runAsync("INSERT OR REPLACE INTO bills (id, locale_id, data, cached_at) VALUES (?, ?, ?, ?)", [
                b.id,
                swayLocaleId,
                JSON.stringify(b),
                now,
            ]);
        }
    });
}

export async function clear(): Promise<void> {
    const d = await openDatabase();
    await d.runAsync("DELETE FROM bills");
}

export async function clearOne(id: number): Promise<void> {
    const d = await openDatabase();
    await d.runAsync("DELETE FROM bills WHERE id = ?", [id]);
}
