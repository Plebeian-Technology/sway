// @lat: [[bill-detail-error-recovery#When a bill will not load on the phone]]
// @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";

export type BillData = Record<string, unknown> & {
    bill?: Record<string, unknown>;
    sponsor?: Record<string, unknown>;
    bill_score?: Record<string, unknown>;
    user_vote?: Record<string, unknown> | null;
    districts?: Record<string, unknown>[];
    organizations?: Record<string, unknown>[];
};

export interface UseBillResult {
    data: BillData | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useBill(id: number): UseBillResult {
    const [data, setData] = useState<BillData | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            // @lat: [[lazy-inertia-props#Mobile JSON omission is an explicit request]]
            const res = await apiClient.get<BillData>(`${Routes.bill(id)}?with=legislator`, {
                headers: { "X-Sway-Omit-Props": "legislators,legislator_votes,public_testimony_letters" },
                signal: ctrl.signal,
            });
            if (ctrl.signal.aborted) return;
            setData(res);
            setError(null);
        } catch (e: unknown) {
            // @lat: [[mobile-bill-hooks#useBill]]
            if (ctrl.signal.aborted || (e instanceof ApiRequestError && e.code === "aborted")) {
                return;
            }
            setError(e instanceof Error ? e : new Error(String(e)));
        } finally {
            if (abortRef.current === ctrl) {
                setLoading(false);
            }
        }
    }, [id]);

    useEffect(() => {
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [refresh]);

    return { data, loading, error, refresh };
}
