/**
 * billCache — keeps bills in SQLite on the device, capped at 20 per locale.
 * Once the cap is reached, each new bill pushes the oldest one out.
 */
jest.mock("expo-sqlite", () => {
    // @lat: [[mobile-sqlite-cache-design#Why billCache caps rows per locale in a transaction]]
    const rows = new Map<number, { id: number; locale_id: number; data: string; cached_at: number }>();

    const matchSelect = (sql: string) =>
        /select\s+data,\s+cached_at\s+from\s+bills\s+where\s+locale_id\s+=\s+\?\s+order\s+by\s+cached_at\s+desc\s+limit\s+24/i.test(
            sql,
        );
    const matchDeleteByLocale = (sql: string) => /delete\s+from\s+bills\s+where\s+locale_id\s+=\s+\?/i.test(sql);
    const matchDeleteAll = (sql: string) => /^delete\s+from\s+bills\s*$/i.test(sql.trim());
    const matchUpsert = (sql: string) =>
        /insert\s+or\s+replace\s+into\s+bills\s+\(id,\s+locale_id,\s+data,\s+cached_at\)/i.test(sql);

    const db = {
        execAsync: jest.fn(async () => {}),
        runAsync: jest.fn(async (sql: string, params: unknown[] = []) => {
            if (matchUpsert(sql)) {
                const [id, locale_id, data, cached_at] = params as [number, number, string, number];
                rows.set(id, { id, locale_id, data, cached_at });
            } else if (matchDeleteByLocale(sql)) {
                const swayLocaleId = Number(params[0]);
                for (const [id, r] of rows) if (r.locale_id === swayLocaleId) rows.delete(id);
            } else if (matchDeleteAll(sql)) {
                rows.clear();
            }
            return { changes: 1, lastInsertRowId: 0 };
        }),
        getAllAsync: jest.fn(async (sql: string, params: unknown[] = []) => {
            if (matchSelect(sql)) {
                const swayLocaleId = Number(params[0]);
                const out = Array.from(rows.values())
                    .filter((r) => r.locale_id === swayLocaleId)
                    .sort((a, b) => b.cached_at - a.cached_at)
                    .slice(0, 24)
                    .map((r) => ({ data: r.data, cached_at: r.cached_at }));
                return out;
            }
            return [];
        }),
        getFirstAsync: jest.fn(async () => null),
        closeAsync: jest.fn(async () => {}),
        withTransactionAsync: jest.fn(async (fn: () => Promise<void>) => fn()),
    };

    return {
        openDatabaseAsync: jest.fn(async () => db),
        __reset: () => rows.clear(),
        __db: db,
    };
});

import * as billCache from "../../src/cache/billCache";
import { closeDatabase } from "../../src/cache/db";
// oxlint-disable-next-line @typescript-eslint/no-require-imports
const sqliteMock = require("expo-sqlite") as { __reset: () => void };

describe("billCache", () => {
    beforeEach(async () => {
        sqliteMock.__reset();
        await closeDatabase();
    });

    test("set + get round-trip returns rows sorted by cached_at desc", async () => {
        await billCache.set(1, [
            { id: 10, title: "A" },
            { id: 11, title: "B" },
        ]);
        const rows = await billCache.get(1);
        expect(rows).toHaveLength(2);
        const titles = rows.map((r) => (r.bill as { title: string }).title);
        expect(titles).toEqual(expect.arrayContaining(["A", "B"]));
    });

    test("set keeps at most 24 rows per locale (LIMIT 24)", async () => {
        const big = Array.from({ length: 30 }, (_, i) => ({ id: 1000 + i, title: `T${i}` }));
        await billCache.set(2, big);
        const rows = await billCache.get(2);
        expect(rows.length).toBeLessThanOrEqual(24);
    });

    test("clear() empties the table", async () => {
        await billCache.set(1, [{ id: 1, title: "X" }]);
        await billCache.clear();
        const rows = await billCache.get(1);
        expect(rows).toHaveLength(0);
    });

    test("set replaces previous rows for the same locale", async () => {
        await billCache.set(1, [{ id: 1, title: "old" }]);
        await billCache.set(1, [{ id: 2, title: "new" }]);
        const rows = await billCache.get(1);
        const titles = rows.map((r) => (r.bill as { title: string }).title);
        expect(titles).toContain("new");
        expect(titles).not.toContain("old");
    });
});
