// @lat: [[surfaces#Delivery surfaces#The /api/v1 mobile API]]
import { useCallback, useEffect, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";

export const NOTIFICATION_PREF_KEYS = [
    "botm_announcement",
    "legislator_voted",
    "vote_window_closing",
    "org_position_taken",
] as const;

export type NotificationPrefKey = (typeof NOTIFICATION_PREF_KEYS)[number];

export interface NotificationPref {
    key: NotificationPrefKey;
    enabled: boolean;
    updated_at?: string;
}

export interface UseNotificationPrefsResult {
    prefs: NotificationPref[];
    loading: boolean;
    error: Error | null;
    toggle: (key: NotificationPrefKey, next: boolean) => Promise<void>;
    refresh: () => Promise<void>;
}

function defaultPrefs(): NotificationPref[] {
    return NOTIFICATION_PREF_KEYS.map((k) => ({
        key: k,
        enabled: k === "botm_announcement",
    }));
}

export function useNotificationPrefs(): UseNotificationPrefsResult {
    const [prefs, setPrefs] = useState<NotificationPref[]>(defaultPrefs());
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const rows = await apiClient.get<
                (NotificationPref | { key: string; enabled: boolean; updated_at?: string })[]
            >(Routes.notificationPreferences());
            const byKey = new Map(rows.map((r) => [r.key, r]));
            const botmRow = byKey.get("botm_announcement");

            setPrefs(
                NOTIFICATION_PREF_KEYS.map((k) => {
                    if (k === "botm_announcement") {
                        if (botmRow) {
                            return {
                                key: "botm_announcement",
                                enabled: botmRow.enabled,
                                updated_at: botmRow.updated_at,
                            };
                        }
                        return { key: "botm_announcement", enabled: true };
                    }
                    const row = byKey.get(k);
                    return row
                        ? { key: k, enabled: row.enabled, updated_at: row.updated_at }
                        : { key: k, enabled: false };
                }),
            );
        } catch (e) {
            setError(e instanceof Error ? e : new Error(String(e)));
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        refresh();
    }, [refresh]);

    const toggle = useCallback(async (key: NotificationPrefKey, next: boolean) => {
        // @lat: [[surfaces#Delivery surfaces#The /api/v1 mobile API]]
        let prevValue = false;
        setPrefs((curr) => {
            const found = curr.find((p) => p.key === key);
            prevValue = found?.enabled ?? false;
            return curr.map((p) => (p.key === key ? { ...p, enabled: next } : p));
        });
        try {
            await apiClient.patch(Routes.notificationPreference(key), { enabled: next });
        } catch (err) {
            setPrefs((curr) => curr.map((p) => (p.key === key ? { ...p, enabled: prevValue } : p)));
            throw err;
        }
    }, []);

    return { prefs, loading, error, toggle, refresh };
}
