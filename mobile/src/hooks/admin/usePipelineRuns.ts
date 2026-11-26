// @lat: [[mobile-admin-area#The pipeline runs screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface PipelineRunRow {
    id: number;
    status: string;
    kind: "single" | "all_bills";
    bill_id: number | null;
    bill_external_id: string | null;
    remote_run_id: string | null;
    started_at: string | null;
    completed_at: string | null;
    current_stage: string | null;
    bills_total: number;
    bills_succeeded: number;
    bills_failed: number;
    failing_stage: string | null;
}

export interface UsePipelineRunsResult {
    runs: PipelineRunRow[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function usePipelineRuns(): UsePipelineRunsResult {
    const [runs, setRuns] = useState<PipelineRunRow[] | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<{ runs: PipelineRunRow[] }>(Routes.adminPipelineRuns(), {
                signal: ctrl.signal,
            });
            if (ctrl.signal.aborted) return;
            setRuns(res.runs);
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

    return { runs, loading, error, refresh };
}
