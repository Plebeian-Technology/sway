jest.mock("expo-sqlite", () => {
    const rows = new Map<number, { id: number; locale_id: number; data: string; cached_at: number }>();

    const matchSelect = (sql: string) =>
        /select\s+data,\s+cached_at\s+from\s+legislators\s+where\s+locale_id\s+=\s+\?\s+order\s+by\s+cached_at\s+desc\s+limit\s+50/i.test(
            sql,
        );
    const matchDeleteByLocale = (sql: string) => /delete\s+from\s+legislators\s+where\s+locale_id\s+=\s+\?/i.test(sql);
    const matchDeleteAll = (sql: string) => /^delete\s+from\s+legislators\s*$/i.test(sql.trim());
    const matchUpsert = (sql: string) =>
        /insert\s+or\s+replace\s+into\s+legislators\s+\(id,\s+locale_id,\s+data,\s+cached_at\)/i.test(sql);

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
                    .slice(0, 50)
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

import * as legislatorCache from "../../src/cache/legislatorCache";
import { closeDatabase } from "../../src/cache/db";
// oxlint-disable-next-line @typescript-eslint/no-require-imports
const sqliteMock = require("expo-sqlite") as { __reset: () => void };

// @lat: [[mobile-sqlite-cache-design#Why legislatorCache caps rows per locale]]
describe("legislatorCache", () => {
    beforeEach(async () => {
        sqliteMock.__reset();
        await closeDatabase();
    });

    test("set + get round-trip returns rows sorted by cached_at desc", async () => {
        await legislatorCache.set(1, [
            { id: 10, full_name: "Alice" },
            { id: 11, full_name: "Bob" },
        ]);
        const rows = await legislatorCache.get(1);
        expect(rows).toHaveLength(2);
        const names = rows.map((r) => (r.legislator as { full_name: string }).full_name);
        expect(names).toEqual(expect.arrayContaining(["Alice", "Bob"]));
        expect(rows[0].cachedAt).toBeGreaterThan(0);
    });

    test("set keeps at most 50 rows per locale (LIMIT 50)", async () => {
        const big = Array.from({ length: 65 }, (_, i) => ({ id: 1000 + i, full_name: `Leg${i}` }));
        await legislatorCache.set(2, big);
        const rows = await legislatorCache.get(2);
        expect(rows.length).toBe(50);
        expect(rows.length).toBeLessThanOrEqual(50);
    });

    test("locale isolation: rows for locale 1 are isolated from locale 2", async () => {
        await legislatorCache.set(1, [{ id: 101, full_name: "Locale 1 Rep" }]);
        await legislatorCache.set(2, [{ id: 201, full_name: "Locale 2 Rep" }]);

        const loc1 = await legislatorCache.get(1);
        const loc2 = await legislatorCache.get(2);

        expect(loc1).toHaveLength(1);
        expect((loc1[0].legislator as { full_name: string }).full_name).toBe("Locale 1 Rep");

        expect(loc2).toHaveLength(1);
        expect((loc2[0].legislator as { full_name: string }).full_name).toBe("Locale 2 Rep");
    });

    test("clear() empties the table across all locales", async () => {
        await legislatorCache.set(1, [{ id: 1, full_name: "Rep A" }]);
        await legislatorCache.set(2, [{ id: 2, full_name: "Rep B" }]);
        await legislatorCache.clear();
        const rows1 = await legislatorCache.get(1);
        const rows2 = await legislatorCache.get(2);
        expect(rows1).toHaveLength(0);
        expect(rows2).toHaveLength(0);
    });

    test("set replaces previous rows for the same locale", async () => {
        await legislatorCache.set(1, [{ id: 1, full_name: "Old Rep" }]);
        await legislatorCache.set(1, [{ id: 2, full_name: "New Rep" }]);
        const rows = await legislatorCache.get(1);
        expect(rows).toHaveLength(1);
        const names = rows.map((r) => (r.legislator as { full_name: string }).full_name);
        expect(names).toContain("New Rep");
        expect(names).not.toContain("Old Rep");
    });
});
