// @lat: [[mobile-admin-area#The bill summary reports screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export type BillSummaryReportStatus = "pending" | "reviewed" | "resolved" | "dismissed";

export interface BillSummaryReportRow {
    id: number;
    bill_id: number;
    reason_label: string;
    details: string | null;
    status: BillSummaryReportStatus;
    created_at: string;
    reporter_display: string;
    bill_title: string;
    bill_external_id: string;
    sway_locale_name: string | null;
}

export interface BillSummaryReportStatusCounts {
    all: number;
    pending: number;
    reviewed: number;
    resolved: number;
    dismissed: number;
}

export interface BillSummaryReportLocale {
    id: number;
    name: string;
}

export interface BillSummaryReportsPage {
    reports: BillSummaryReportRow[];
    status_counts: BillSummaryReportStatusCounts;
    locales: BillSummaryReportLocale[];
}

export interface UseBillSummaryReportsResult {
    data: BillSummaryReportsPage | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useBillSummaryReports(status: string, localeId: number | null): UseBillSummaryReportsResult {
    const [data, setData] = useState<BillSummaryReportsPage | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<BillSummaryReportsPage>(Routes.adminBillSummaryReports(status, localeId), {
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
    }, [status, localeId]);

    useEffect(() => {
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [refresh]);

    return { data, loading, error, refresh };
}
