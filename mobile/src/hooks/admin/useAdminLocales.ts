// @lat: [[mobile-admin-area#The locales screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface AdminLocaleRow {
    id: number;
    label: string;
    user_count: number;
    sample_street: string | null;
    sample_postal_code: string | null;
    sample_latitude: number | null;
    sample_longitude: number | null;
}

export interface AdminLocaleTier {
    key: string;
    label: string;
    locales: AdminLocaleRow[];
}

export interface AdminLocales {
    tiers: AdminLocaleTier[];
}

export interface UseAdminLocalesResult {
    data: AdminLocales | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useAdminLocales(): UseAdminLocalesResult {
    const [data, setData] = useState<AdminLocales | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<AdminLocales>(Routes.adminLocales(), { signal: ctrl.signal });
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
