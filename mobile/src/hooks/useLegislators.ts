// @lat: [[mobile-use-legislators-hook#Parameters]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";
import * as legislatorCache from "../cache/legislatorCache";

export type LegislatorAgreeableScore = {
    count_agreed?: number | string;
    count_disagreed?: number | string;
    count_no_legislator_vote?: number | string;
    count_legislator_abstained?: number | string;
};

export type LegislatorScorePair = LegislatorAgreeableScore & {
    legislator_district_score?: LegislatorAgreeableScore | null;
    legislator_locale_score?: LegislatorAgreeableScore | null;
};

// @lat: [[mobile-use-legislators-hook#Return value]]
export type LegislatorRecord = {
    id: number;
    full_name?: string;
    title?: string;
    party?: string;
    district_name?: string;
    email?: string;
    phone?: string;
    photo_url?: string | null;
    twitter?: string | null;
    link?: string | null;
    active?: boolean;
    term_start_year?: number | null;
    term_end_year?: number | null;
    district?: {
        name?: string;
        number?: number | string;
        region_code?: string;
    } | null;
    user_legislator_score?: LegislatorScorePair | null;
    lifetime_score?: LegislatorScorePair | null;
} & Record<string, unknown>;

export interface LegislatorHistoryTerm {
    term_start_year: number;
    term_end_year: number;
    title?: string;
    district?: LegislatorRecord["district"];
}

export type LegislatorHistoryEndedReason = "term_ended" | "district_changed" | "link_inactive";

export interface LegislatorHistoryEntry {
    legislator: LegislatorRecord;
    term: LegislatorHistoryTerm;
    score: LegislatorAgreeableScore;
    ended_reason: LegislatorHistoryEndedReason;
}

export interface LegislatorHistorySession {
    session_label: string;
    entries: LegislatorHistoryEntry[];
}

export interface LegislatorHistory {
    sessions: LegislatorHistorySession[];
}

interface LegislatorsResponse {
    legislators?: LegislatorRecord[];
    // @lat: [[mobile-use-legislators-hook#waitingForNewTerm]]
    waiting_for_new_term?: boolean;
    history?: LegislatorHistory;
}

export interface UseLegislatorsResult {
    data: LegislatorRecord[];
    waitingForNewTerm: boolean;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
    isOnline: boolean;
    history: LegislatorHistory | null;
    historyLoading: boolean;
    historyError: Error | null;
    fetchHistory: (swayLocaleId?: number) => Promise<void>;
}

export interface UseLegislatorsOptions {
    swayLocaleId?: number;
}

const pathForLocale = (swayLocaleId?: number) =>
    swayLocaleId ? `${Routes.legislators()}?sway_locale_id=${swayLocaleId}` : Routes.legislators();

interface HistoryState {
    loadingPath: string | null;
    resolvedPath: string | null;
    data: LegislatorHistory | null;
    error: Error | null;
}

const NO_HISTORY: HistoryState = { loadingPath: null, resolvedPath: null, data: null, error: null };

export function useLegislators(options?: UseLegislatorsOptions): UseLegislatorsResult {
    const swayLocaleId = options?.swayLocaleId;
    const [data, setData] = useState<LegislatorRecord[]>([]);
    const [waitingForNewTerm, setWaitingForNewTerm] = useState(false);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);
    const [historyState, setHistoryState] = useState<HistoryState>(NO_HISTORY);
    const generationRef = useRef<number>(0);
    const prevLocaleIdRef = useRef<number | undefined>(swayLocaleId);
    const hydratedLocaleRef = useRef<number | undefined>(undefined);

    const path = pathForLocale(swayLocaleId);

    // @lat: [[mobile-sqlite-cache-design#Why useLegislators reads and writes legislatorCache per locale]]
    const refresh = useCallback(async () => {
        const currentGen = ++generationRef.current;
        setLoading(true);
        if (prevLocaleIdRef.current !== swayLocaleId) {
            prevLocaleIdRef.current = swayLocaleId;
            hydratedLocaleRef.current = undefined;
            setData([]);
            setWaitingForNewTerm(false);
            setError(null);
        }
        if (typeof swayLocaleId === "number" && swayLocaleId > 0 && hydratedLocaleRef.current !== swayLocaleId) {
            try {
                const cached = await legislatorCache.get(swayLocaleId);
                if (generationRef.current !== currentGen) return;
                if (Array.isArray(cached) && cached.length > 0) {
                    hydratedLocaleRef.current = swayLocaleId;
                    setData(cached.map((c) => c.legislator as LegislatorRecord));
                }
            } catch {}
        }
        try {
            const res = await apiClient.get<LegislatorsResponse | LegislatorRecord[]>(path);
            if (generationRef.current !== currentGen) return;
            hydratedLocaleRef.current = swayLocaleId;
            const fresh = Array.isArray(res) ? res : (res?.legislators ?? []);
            setData(fresh);
            setWaitingForNewTerm(Array.isArray(res) ? false : res?.waiting_for_new_term === true);
            setError(null);
            if (typeof swayLocaleId === "number" && swayLocaleId > 0) {
                try {
                    await legislatorCache.set(swayLocaleId, fresh);
                } catch {}
            }
        } catch (e: unknown) {
            if (generationRef.current !== currentGen) return;
            if (e instanceof ApiRequestError && e.code === "aborted") return;
            setError(e instanceof Error ? e : new Error(String(e)));
        } finally {
            if (generationRef.current === currentGen) {
                setLoading(false);
            }
        }
    }, [path, swayLocaleId]);

    const fetchHistory = useCallback(
        async (overrideSwayLocaleId?: number) => {
            const targetPath = overrideSwayLocaleId === undefined ? path : pathForLocale(overrideSwayLocaleId);
            setHistoryState((prev) => ({ ...prev, loadingPath: targetPath }));
            try {
                const res = await apiClient.get<LegislatorsResponse | LegislatorRecord[]>(targetPath);
                setHistoryState({
                    loadingPath: null,
                    resolvedPath: targetPath,
                    data: Array.isArray(res) ? { sessions: [] } : (res?.history ?? { sessions: [] }),
                    error: null,
                });
            } catch (e: unknown) {
                if (e instanceof ApiRequestError && e.code === "aborted") return;
                setHistoryState({
                    loadingPath: null,
                    resolvedPath: targetPath,
                    data: null,
                    error: e instanceof Error ? e : new Error(String(e)),
                });
            }
        },
        [path],
    );

    useEffect(() => {
        void refresh();
        return () => {
            generationRef.current += 1;
        };
    }, [refresh]);

    const isCurrentLocale = historyState.resolvedPath === path;

    return {
        data,
        waitingForNewTerm,
        loading,
        error,
        refresh,
        isOnline: true,
        history: isCurrentLocale ? historyState.data : null,
        historyLoading: historyState.loadingPath === path,
        historyError: isCurrentLocale ? historyState.error : null,
        fetchHistory,
    };
}
