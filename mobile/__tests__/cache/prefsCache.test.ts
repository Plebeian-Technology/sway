// @lat: [[mobile-locale-override-design#Why prefsCache stores the chosen jurisdiction in SQLite]]

jest.mock("expo-sqlite", () => {
    const rows = new Map<string, { key: string; value: string }>();

    const db = {
        execAsync: jest.fn(async (_sql: string) => {}),
        runAsync: jest.fn(async (sql: string, params: unknown[] = []) => {
            const lower = sql.trim().toLowerCase();
            if (lower.startsWith("insert or replace into prefs")) {
                const [key, value] = params as [string, string];
                rows.set(key, { key, value });
                return { changes: 1, lastInsertRowId: 0 };
            }
            if (lower.startsWith("delete from prefs where key")) {
                rows.delete(String(params[0]));
                return { changes: 1, lastInsertRowId: 0 };
            }
            if (lower.startsWith("delete from prefs")) {
                rows.clear();
                return { changes: 1, lastInsertRowId: 0 };
            }
            return { changes: 0, lastInsertRowId: 0 };
        }),
        getFirstAsync: jest.fn(async (sql: string, params: unknown[] = []) => {
            const lower = sql.trim().toLowerCase();
            if (lower.startsWith("select value from prefs where key")) {
                const r = rows.get(String(params[0]));
                return r ? { value: r.value } : null;
            }
            return null;
        }),
        closeAsync: jest.fn(async () => {}),
    };

    return {
        openDatabaseAsync: jest.fn(async () => db),
        __reset: () => rows.clear(),
    };
});

import { prefsCache, PREFS_KEYS } from "../../src/cache/prefsCache";
import { closeDatabase } from "../../src/cache/db";
// oxlint-disable-next-line @typescript-eslint/no-require-imports
const sqliteMock = require("expo-sqlite") as { __reset: () => void };

describe("prefsCache", () => {
    beforeEach(async () => {
        sqliteMock.__reset();
        await closeDatabase();
    });

    test("pins the literal AsyncStorage/SQLite key for storing the selected locale ID", () => {
        expect(PREFS_KEYS.selectedSwayLocaleId).toBe("selected_locale_id");
    });

    test("set + get round-trip on the selected_locale_id key", async () => {
        await prefsCache.set(PREFS_KEYS.selectedSwayLocaleId, "42");
        expect(await prefsCache.get(PREFS_KEYS.selectedSwayLocaleId)).toBe("42");
    });

    test("get returns null for an unknown key", async () => {
        expect(await prefsCache.get("never_set")).toBeNull();
    });

    test("set is upsert — second set replaces first", async () => {
        await prefsCache.set(PREFS_KEYS.selectedSwayLocaleId, "1");
        await prefsCache.set(PREFS_KEYS.selectedSwayLocaleId, "2");
        expect(await prefsCache.get(PREFS_KEYS.selectedSwayLocaleId)).toBe("2");
    });

    test("delete removes the key", async () => {
        await prefsCache.set(PREFS_KEYS.selectedSwayLocaleId, "42");
        await prefsCache.delete(PREFS_KEYS.selectedSwayLocaleId);
        expect(await prefsCache.get(PREFS_KEYS.selectedSwayLocaleId)).toBeNull();
    });
});
