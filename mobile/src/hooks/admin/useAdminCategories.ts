// @lat: [[mobile-admin-area#The categories screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface AdminCategory {
    id: number;
    name: string;
    slug: string;
    active: boolean;
    bill_count: number;
}

export interface AdminCategories {
    categories: AdminCategory[];
}

export interface UseAdminCategoriesResult {
    data: AdminCategories | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useAdminCategories(): UseAdminCategoriesResult {
    const [data, setData] = useState<AdminCategories | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<AdminCategories>(Routes.adminCategories(), { signal: ctrl.signal });
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
