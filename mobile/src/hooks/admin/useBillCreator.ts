// @lat: [[mobile-bill-creator#The bill creator screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export const BILL_CREATOR_TABS = ["creator", "schedule", "pipeline", "summary", "positions"] as const;

export type BillCreatorTab = (typeof BILL_CREATOR_TABS)[number];

export interface BillCreatorProps {
    bill?: { id: number | null; external_id: string | null; title: string | null };
    [prop: string]: unknown;
}

export interface BillCreatorTabProps {
    billId: number | null;
    data: BillCreatorProps;
    refresh: () => Promise<void>;
}

export interface UseBillCreatorResult {
    data: BillCreatorProps | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useBillCreator(billId: number | null, tab: BillCreatorTab): UseBillCreatorResult {
    const [data, setData] = useState<BillCreatorProps | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<BillCreatorProps>(Routes.adminBillCreatorTab(billId, tab), {
                signal: ctrl.signal,
            });
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
    }, [billId, tab]);

    useEffect(() => {
        // @lat: [[mobile-bill-creator#The bill creator screen#A tab never sees another tab's props]]
        setData(null);
        setError(null);
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [refresh]);

    return { data, loading, error, refresh };
}
