// @lat: [[mobile-sqlite-cache-design#Tables and schema layout]]
import { openDatabase } from "./db";

export interface CachedVote {
    vote: Record<string, unknown>;
    cachedAt: number;
}

export async function get(billId: number): Promise<CachedVote | null> {
    const d = await openDatabase();
    const row = await d.getFirstAsync<{ data: string; cached_at: number }>(
        "SELECT data, cached_at FROM user_votes WHERE bill_id = ?",
        [billId],
    );
    if (!row) return null;
    return { vote: JSON.parse(row.data) as Record<string, unknown>, cachedAt: row.cached_at };
}

export async function set(billId: number, vote: Record<string, unknown>): Promise<void> {
    const d = await openDatabase();
    await d.runAsync("INSERT OR REPLACE INTO user_votes (bill_id, data, cached_at) VALUES (?, ?, ?)", [
        billId,
        JSON.stringify(vote),
        Date.now(),
    ]);
}

export async function clear(): Promise<void> {
    const d = await openDatabase();
    await d.runAsync("DELETE FROM user_votes");
}
