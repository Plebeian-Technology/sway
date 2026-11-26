// @lat: [[mobile-admin-area#The partner reports screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface PartnerArticleReport {
    id: number;
    bill_id: number;
    bill_title: string | null;
    article_title: string;
    article_url: string;
    published_at: string | null;
    clicks_count: number;
    registrations_count: number;
    votes_count: number;
    sentiment_suppressed: boolean;
    pro_votes_count: number | null;
    con_votes_count: number | null;
}

export interface PartnerReport {
    partner_slug: string;
    partner_name: string;
    articles_count: number;
    bills_count: number;
    total_clicks: number;
    total_registrations: number;
    total_votes: number;
    pro_percentage: number | null;
    con_percentage: number | null;
    sentiment_suppressed?: boolean;
    articles: PartnerArticleReport[];
}

export interface UsePartnerReportsResult {
    data: PartnerReport[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function usePartnerReports(): UsePartnerReportsResult {
    const [data, setData] = useState<PartnerReport[] | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<PartnerReport[]>(Routes.adminPartnerReports(), { signal: ctrl.signal });
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
