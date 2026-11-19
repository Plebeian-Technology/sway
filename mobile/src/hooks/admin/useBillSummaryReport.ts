// @lat: [[mobile-admin-area#The bill summary report screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";
import type { BillSummaryReportRow } from "./useBillSummaryReports";

export interface BillSummaryReport extends BillSummaryReportRow {
    summary_snapshot: string | null;
    summary_ai_unreviewed: boolean;
    bill_current_summary: string | null;
    admin_notes: string | null;
    resolved_at: string | null;
    resolved_by_name: string | null;
}

export interface UseBillSummaryReportResult {
    data: BillSummaryReport | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useBillSummaryReport(id: number): UseBillSummaryReportResult {
    const [data, setData] = useState<BillSummaryReport | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<BillSummaryReport>(Routes.adminBillSummaryReport(id), {
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
    }, [id]);

    useEffect(() => {
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [refresh]);

    return { data, loading, error, refresh };
}
