// @lat: [[mobile-admin-area#The registration funnel screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface FunnelStep {
    step: string;
    label: string;
    visitor_count: number;
    step_conversion_rate: number;
    drop_off_count: number;
    drop_off_rate: number;
    conversion_rate_from_start: number;
}

export interface FrictionPoint {
    from_step: string;
    to_step: string;
    label: string;
    drop_off_count: number;
    drop_off_rate: number;
    rank_by_count: number;
    rank_by_rate: number;
}

export interface AttributionBreakdown {
    source: string;
    visitors_count: number;
    registrations_count: number;
    votes_count: number;
    conversion_rate: number;
    vote_rate: number;
}

export interface LatencyMetrics {
    sample_count: number;
    avg_seconds: number;
    median_seconds: number;
    p95_seconds: number;
    min_seconds: number;
    max_seconds: number;
}

export type FunnelTraffic = "humans" | "bots" | "all";

export interface RegistrationFunnel {
    time_range: string;
    filter_attribution_key: string | null;
    steps: FunnelStep[];
    overall_conversion_rate: number;
    friction_points: FrictionPoint[];
    attributions: AttributionBreakdown[];
    latency: LatencyMetrics;
    time_ranges: { id: string; label: string }[];
    traffic: FunnelTraffic;
    traffic_options: { id: FunnelTraffic; label: string }[];
    bot_visitor_count: number;
}

export interface UseRegistrationFunnelResult {
    data: RegistrationFunnel | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useRegistrationFunnel(
    timeRange: string,
    traffic: FunnelTraffic,
    attributionKey: string | null,
): UseRegistrationFunnelResult {
    const [data, setData] = useState<RegistrationFunnel | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<RegistrationFunnel>(
                Routes.adminRegistrationFunnel(timeRange, traffic, attributionKey),
                { signal: ctrl.signal },
            );
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
    }, [timeRange, traffic, attributionKey]);

    useEffect(() => {
        void refresh();
        return () => {
            abortRef.current?.abort();
        };
    }, [refresh]);

    return { data, loading, error, refresh };
}
