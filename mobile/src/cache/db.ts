// @lat: [[mobile-sqlite-cache-design#Why purgeAll empties every table]]
import * as SQLite from "expo-sqlite";

let db: SQLite.SQLiteDatabase | null = null;
let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS bootstrap_cache (
  user_id TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  fetched_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS bills (
  id INTEGER PRIMARY KEY,
  locale_id INTEGER NOT NULL,
  data TEXT NOT NULL,
  cached_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bills_locale ON bills(locale_id, cached_at);
CREATE TABLE IF NOT EXISTS user_votes (
  bill_id INTEGER PRIMARY KEY,
  data TEXT NOT NULL,
  cached_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS legislators (
  id INTEGER PRIMARY KEY,
  locale_id INTEGER NOT NULL,
  data TEXT NOT NULL,
  cached_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS prefs (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`;

export async function openDatabase(): Promise<SQLite.SQLiteDatabase> {
    if (db) return db;
    if (!dbPromise) {
        dbPromise = (async () => {
            const database = await SQLite.openDatabaseAsync("sway_cache.db");
            await database.execAsync(SCHEMA);
            db = database;
            return database;
        })().catch((err) => {
            dbPromise = null;
            throw err;
        });
    }
    return dbPromise;
}

export async function closeDatabase(): Promise<void> {
    if (dbPromise) {
        try {
            const database = await dbPromise;
            await database.closeAsync();
        } catch {}
        dbPromise = null;
        db = null;
        return;
    }
    if (db) {
        await db.closeAsync();
        db = null;
    }
}

export function resetDatabaseForTests(): void {
    db = null;
    dbPromise = null;
}

export async function purgeAll(): Promise<void> {
    const d = await openDatabase();
    await d.execAsync(
        "DELETE FROM bootstrap_cache; DELETE FROM bills; DELETE FROM user_votes; DELETE FROM legislators; DELETE FROM prefs;",
    );
}
