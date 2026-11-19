// @lat: [[mobile-admin-area#The system prompts screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface SystemPromptEntry {
    id: string;
    label: string;
    purpose: string;
    builder: string;
    model: string;
    model_setting_label: string;
    system_prompt: string | null;
    character_count: number | null;
    unavailable_reason: string | null;
    sway_locale_name: string | null;
}

export interface SystemPromptCatalog {
    models: { summarization: string; classification: string };
    active_category_count: number;
    llm_settings_path: string;
    prompts: SystemPromptEntry[];
}

export interface UseSystemPromptsResult {
    catalog: SystemPromptCatalog | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useSystemPrompts(): UseSystemPromptsResult {
    const [catalog, setCatalog] = useState<SystemPromptCatalog | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<SystemPromptCatalog>(Routes.adminSystemPrompts(), { signal: ctrl.signal });
            if (ctrl.signal.aborted) return;
            setCatalog(res);
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

    return { catalog, loading, error, refresh };
}
