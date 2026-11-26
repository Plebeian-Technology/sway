// @lat: [[mobile-bill-creator#Sections#The run selector section]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import type { BillCreatorProps } from "./useBillCreator";

export interface UsePinnedPipelineRunResult {
    data: BillCreatorProps | null;
    refresh: () => Promise<void>;
}

export function usePinnedPipelineRun(billId: number | null, runId: number | null): UsePinnedPipelineRunResult {
    const [data, setData] = useState<BillCreatorProps | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        if (runId === null) return;
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        try {
            const res = await apiClient.get<BillCreatorProps>(Routes.adminBillCreatorPipelineRun(billId, runId), {
                signal: ctrl.signal,
            });
            if (!ctrl.signal.aborted) setData(res);
        } catch {
            // A failed fetch keeps the data already shown.
        }
    }, [billId, runId]);

    useEffect(() => {
        setData(null);
        void refresh();
        return () => abortRef.current?.abort();
    }, [refresh]);

    return { data, refresh };
}
