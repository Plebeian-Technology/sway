import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";
import type { ILegislator } from "../types/legislator";

export interface UseLegislatorResult {
    data: ILegislator | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

interface FetchState {
    id: number;
    data: ILegislator | null;
    loading: boolean;
    error: Error | null;
}

// @lat: [[legislator-botm-record#The phone fetches the detail response]]
export function useLegislator(legislatorId: number): UseLegislatorResult {
    const [state, setState] = useState<FetchState>({
        id: legislatorId,
        data: null,
        loading: true,
        error: null,
    });
    const controllerRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        controllerRef.current?.abort();
        const controller = new AbortController();
        controllerRef.current = controller;
        setState((prev) => ({
            id: legislatorId,
            data: prev.id === legislatorId ? prev.data : null,
            loading: true,
            error: null,
        }));
        try {
            const res = await apiClient.get<{ legislator?: ILegislator } & ILegislator>(
                Routes.legislator(legislatorId),
                { signal: controller.signal },
            );
            if (controllerRef.current !== controller) return;
            setState({ id: legislatorId, data: res.legislator ?? res, loading: false, error: null });
        } catch (e: unknown) {
            if (controllerRef.current !== controller) return;
            if (e instanceof ApiRequestError && e.code === "aborted") return;
            const error = e instanceof Error ? e : new Error(String(e));
            setState((prev) => ({
                id: legislatorId,
                data: prev.id === legislatorId ? prev.data : null,
                loading: false,
                error,
            }));
        }
    }, [legislatorId]);

    useEffect(() => {
        void refresh();
        return () => {
            controllerRef.current?.abort();
            controllerRef.current = null;
        };
    }, [refresh]);

    const isCurrentId = state.id === legislatorId;
    return {
        data: isCurrentId ? state.data : null,
        loading: isCurrentId ? state.loading : true,
        error: isCurrentId ? state.error : null,
        refresh,
    };
}
