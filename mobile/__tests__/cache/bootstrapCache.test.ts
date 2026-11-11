/**
 * bootstrapCache — the startup data the app fetches once is kept in expo-sqlite,
 * not in SecureStore. Each row is filed under a user_id, or under "anonymous"
 * for signed-out users. Saving again under the same key overwrites the existing
 * row instead of adding a second one.
 */

// @lat: [[mobile-test-infrastructure-notes#billCache.test.ts and bootstrapCache.test.ts: why the mocked row shape is inline, not a named type]]
jest.mock("expo-sqlite", () => {
    const rows = new Map<string, { user_id: string; payload_json: string; fetched_at: number }>();

    const db = {
        execAsync: jest.fn(async (_sql: string) => {}),
        runAsync: jest.fn(async (sql: string, params: unknown[] = []) => {
            const lower = sql.trim().toLowerCase();
            if (lower.startsWith("insert or replace into bootstrap_cache")) {
                const [user_id, payload_json, fetched_at] = params as [string, string, number];
                rows.set(user_id, { user_id, payload_json, fetched_at });
                return { changes: 1, lastInsertRowId: 0 };
            }
            if (lower.startsWith("delete from bootstrap_cache where user_id")) {
                rows.delete(String(params[0]));
                return { changes: 1, lastInsertRowId: 0 };
            }
            if (lower.startsWith("delete from bootstrap_cache")) {
                rows.clear();
                return { changes: 1, lastInsertRowId: 0 };
            }
            return { changes: 0, lastInsertRowId: 0 };
        }),
        getFirstAsync: jest.fn(async (sql: string, params: unknown[] = []) => {
            const lower = sql.trim().toLowerCase();
            if (lower.startsWith("select payload_json, fetched_at from bootstrap_cache")) {
                const r = rows.get(String(params[0]));
                if (!r) return null;
                return { payload_json: r.payload_json, fetched_at: r.fetched_at };
            }
            return null;
        }),
        getAllAsync: jest.fn(async () => []),
        closeAsync: jest.fn(async () => {}),
        withTransactionAsync: jest.fn(async (fn: () => Promise<void>) => fn()),
    };

    return {
        openDatabaseAsync: jest.fn(async () => db),
        __reset: () => rows.clear(),
        __db: db,
    };
});

import { bootstrapCache } from "../../src/cache/bootstrapCache";
import { closeDatabase, openDatabase, resetDatabaseForTests } from "../../src/cache/db";
// oxlint-disable-next-line @typescript-eslint/no-require-imports
const sqliteMock = require("expo-sqlite") as {
    openDatabaseAsync: jest.Mock;
    __reset: () => void;
    __db: any;
};

describe("bootstrapCache", () => {
    beforeEach(async () => {
        sqliteMock.__reset();
        await closeDatabase();
    });

    test("set + get round-trip preserves payload + fetchedAt", async () => {
        const payload = { current_user: { id: 7 }, locale: { id: 1 }, feature_flags: {} };
        const t0 = Date.now();
        await bootstrapCache.set("7", payload);
        const out = await bootstrapCache.get<typeof payload>("7");
        expect(out).not.toBeNull();
        expect(out!.payload).toEqual(payload);
        expect(out!.fetchedAt.getTime()).toBeGreaterThanOrEqual(t0);
    });

    test("get returns null for unknown userId", async () => {
        const out = await bootstrapCache.get("unknown");
        expect(out).toBeNull();
    });

    test("set twice for same userId UPSERTs (only one row)", async () => {
        await bootstrapCache.set("7", { v: 1 });
        await bootstrapCache.set("7", { v: 2 });
        const out = await bootstrapCache.get<{ v: number }>("7");
        expect(out!.payload.v).toBe(2);
    });

    test("purge() removes all rows", async () => {
        await bootstrapCache.set("7", { x: 1 });
        await bootstrapCache.set("anonymous", { x: 0 });
        await bootstrapCache.purge();
        expect(await bootstrapCache.get("7")).toBeNull();
        expect(await bootstrapCache.get("anonymous")).toBeNull();
    });

    test("get returns null on malformed payload_json", async () => {
        const db = sqliteMock.__db;
        await db.runAsync(
            "INSERT OR REPLACE INTO bootstrap_cache (user_id, payload_json, fetched_at) VALUES (?, ?, ?)",
            ["broken", "{not-json", Date.now()],
        );
        const out = await bootstrapCache.get("broken");
        expect(out).toBeNull();
    });

    test("preserves bootstrap payload with bill_of_the_month and null", async () => {
        const payloadCanonical = {
            current_user: { id: 7 },
            bill_of_the_month: { id: 101, title: "Monthly Bill" },
        };
        await bootstrapCache.set("7", payloadCanonical);
        const outCanonical = await bootstrapCache.get<typeof payloadCanonical>("7");
        expect(outCanonical!.payload.bill_of_the_month).toEqual({ id: 101, title: "Monthly Bill" });

        const payloadNull = {
            current_user: { id: 7 },
            bill_of_the_month: null,
        };
        await bootstrapCache.set("7", payloadNull);
        const outNull = await bootstrapCache.get<typeof payloadNull>("7");
        expect(outNull!.payload.bill_of_the_month).toBeNull();
    });

    test("concurrent cold-start openDatabase callers await SCHEMA execAsync and share one initialization promise", async () => {
        resetDatabaseForTests();
        sqliteMock.openDatabaseAsync.mockClear();
        sqliteMock.__db.execAsync.mockClear();

        let schemaDone = false;
        let resolveSchema!: () => void;
        sqliteMock.__db.execAsync.mockImplementationOnce(
            () =>
                new Promise<void>((resolve) => {
                    resolveSchema = () => {
                        schemaDone = true;
                        resolve();
                    };
                }),
        );

        const p1 = openDatabase();
        const p2 = openDatabase();
        expect(sqliteMock.openDatabaseAsync).toHaveBeenCalledTimes(1);

        let p2ResolvedBeforeSchema = false;
        void p2.then(() => {
            if (!schemaDone) p2ResolvedBeforeSchema = true;
        });

        await Promise.resolve();
        resolveSchema();
        const [d1, d2] = await Promise.all([p1, p2]);
        expect(d1).toBe(d2);
        expect(p2ResolvedBeforeSchema).toBe(false);
    });
});
