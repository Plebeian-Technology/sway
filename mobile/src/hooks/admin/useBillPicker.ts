// @lat: [[mobile-bill-creator#The bill picker]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface PickerBill {
    id: number;
    external_id: string;
    title: string;
}

export interface UseBillPickerResult {
    bills: PickerBill[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useBillPicker(): UseBillPickerResult {
    const [bills, setBills] = useState<PickerBill[] | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<{ bills: PickerBill[] }>(Routes.adminBillCreatorNew(), {
                signal: ctrl.signal,
            });
            if (ctrl.signal.aborted) return;
            setBills(res.bills);
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

    return { bills, loading, error, refresh };
}
