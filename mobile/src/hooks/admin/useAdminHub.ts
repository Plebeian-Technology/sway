// @lat: [[mobile-admin-area#The hub screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface AdminTool {
    id: string;
    label: string;
    description: string;
    path: string;
    group: string;
    external: boolean;
}

export interface AdminDatabaseHealth {
    databases: { name: string; database_bytes: number; wal_bytes: number }[];
    solid_queue_ready: number;
    solid_queue_failed: number;
}

export interface AdminHubData {
    tools: AdminTool[];
    database_health?: AdminDatabaseHealth;
}

export interface UseAdminHubResult {
    data: AdminHubData | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useAdminHub(): UseAdminHubResult {
    const [data, setData] = useState<AdminHubData | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<AdminHubData>(Routes.admin(), { signal: ctrl.signal });
            if (ctrl.signal.aborted) return;
            setData(res);
            setError(null);
        } catch (e: unknown) {
            if (ctrl.signal.aborted || (e instanceof ApiRequestError && e.code === "aborted")) {
                return;
            }
            setError(e instanceof Error ? e : new Error(String(e)));
        } finally {
            if (abortRef.current === ctrl) {
                setLoading(false);
            }
        }
    }, []);

    useEffect(() => {
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [refresh]);

    return { data, loading, error, refresh };
}
