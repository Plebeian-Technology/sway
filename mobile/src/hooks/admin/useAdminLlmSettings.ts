// @lat: [[mobile-admin-area#The LLM settings screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface LlmModelOption {
    id: string;
    label: string;
    selectable: boolean;
    supports_reasoning?: boolean;
}

export interface CatalogModel {
    id: string;
    label: string;
}

export interface AdminLlmSettings {
    supported_models: LlmModelOption[];
    supported_decision_models?: LlmModelOption[];
    supported_extraction_models?: LlmModelOption[];
    available_openrouter_models?: CatalogModel[];
    current_summarization_model: string;
    current_classification_model: string;
    current_decision_model?: string;
    current_extraction_model?: string;
    current_summarization_reasoning_effort?: string | null;
    current_classification_reasoning_effort?: string | null;
    current_summary_batch_enabled: boolean;
    updated_by: { name: string } | null;
    updated_at: string;
}

export interface UseAdminLlmSettingsResult {
    data: AdminLlmSettings | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useAdminLlmSettings(): UseAdminLlmSettingsResult {
    const [data, setData] = useState<AdminLlmSettings | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<AdminLlmSettings>(Routes.adminLlmSettings(), { signal: ctrl.signal });
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
