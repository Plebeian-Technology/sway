// @lat: [[mobile-locale-override-design#Where it is persisted in prefsCache]]
import { openDatabase } from "./db";

interface Row {
    value: string;
}

export const prefsCache = {
    async get(key: string): Promise<string | null> {
        const d = await openDatabase();
        const row = await d.getFirstAsync<Row>("SELECT value FROM prefs WHERE key = ?", [key]);
        return row?.value ?? null;
    },

    async set(key: string, value: string): Promise<void> {
        const d = await openDatabase();
        await d.runAsync("INSERT OR REPLACE INTO prefs (key, value) VALUES (?, ?)", [key, value]);
    },

    async delete(key: string): Promise<void> {
        const d = await openDatabase();
        await d.runAsync("DELETE FROM prefs WHERE key = ?", [key]);
    },
};

export const PREFS_KEYS = {
    selectedSwayLocaleId: "selected_locale_id",
} as const;
