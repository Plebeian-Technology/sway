// @lat: [[mobile-bill-hooks#useBills]]
import { useCallback, useEffect, useRef, useState } from "react";

import { useReachability } from "./useReachability";
import { type UseOfflineCacheResult } from "./useOfflineCache";
import * as billCache from "../cache/billCache";
import { apiClient } from "../api/client";
import { Routes } from "../api/routes";

export type BillRecord = { id: number } & Record<string, unknown>;

export type BillsListMode = "all_bills" | "past_bills_of_the_month";

export interface LegislativeSessionOption {
    id: number;
    name: string;
    active: boolean;
}

export interface BillsApiResponse {
    bills?: BillRecord[];
    bills_total?: number;
    all_categories?: string[];
    list_mode?: BillsListMode;
    legislative_sessions?: LegislativeSessionOption[];
    selected_legislative_session_id?: number | null;
}

export interface UseBillsResult extends UseOfflineCacheResult<BillRecord> {
    page: number;
    billsTotal: number;
    allCategories: string[];
    legislativeSessions: LegislativeSessionOption[];
    selectedLegislativeSessionId: number | null;
    loadingMore: boolean;
    pageError: Error | null;
    hasMore: boolean;
    loadMore: () => Promise<void>;
}

// @lat: [[mobile-bill-hooks#useBillCategories]]
export const capturedCategoriesByLocale: Record<number, string[] | undefined> = {};
export const capturedSessionsByLocale: Record<number, LegislativeSessionOption[] | undefined> = {};
export const inFlightBillsRequests: Record<number, Promise<BillsApiResponse> | undefined> = {};

export function clearCapturedCategories(): void {
    for (const key of Object.keys(capturedCategoriesByLocale)) {
        delete capturedCategoriesByLocale[Number(key)];
    }
    for (const key of Object.keys(capturedSessionsByLocale)) {
        delete capturedSessionsByLocale[Number(key)];
    }
    for (const key of Object.keys(inFlightBillsRequests)) {
        delete inFlightBillsRequests[Number(key)];
    }
}

export interface UseBillsOptions {
    enabled?: boolean;
    listMode?: BillsListMode;
    legislativeSessionId?: number | null;
}

export function useBills(swayLocaleId: number, options?: UseBillsOptions): UseBillsResult {
    const enabled = options?.enabled ?? true;
    const listMode: BillsListMode = options?.listMode ?? "all_bills";
    const legislativeSessionId = options?.legislativeSessionId ?? null;
    const isDefaultAllBills = listMode === "all_bills" && legislativeSessionId === null;

    const [data, setData] = useState<BillRecord[] | null>(null);
    const [loading, setLoading] = useState<boolean>(enabled);
    const [error, setError] = useState<Error | null>(null);
    const [page, setPage] = useState<number>(1);
    const [billsTotal, setBillsTotal] = useState<number>(0);
    const [allCategories, setAllCategories] = useState<string[]>(() => capturedCategoriesByLocale[swayLocaleId] ?? []);
    const [legislativeSessions, setLegislativeSessions] = useState<LegislativeSessionOption[]>(
        () => capturedSessionsByLocale[swayLocaleId] ?? [],
    );
    const [selectedLegislativeSessionId, setSelectedLegislativeSessionId] = useState<number | null>(
        legislativeSessionId,
    );
    const [loadingMore, setLoadingMore] = useState<boolean>(false);
    const [pageError, setPageError] = useState<Error | null>(null);

    const reach = useReachability();
    const mountedRef = useRef<boolean>(true);
    const loadingMoreRef = useRef<boolean>(false);
    const pageRef = useRef<number>(1);
    const generationRef = useRef<number>(0);

    const hasMore = (data?.length ?? 0) < billsTotal;

    const buildBillsPath = useCallback(
        (pageNum: number) => {
            const basePath = listMode === "past_bills_of_the_month" ? Routes.pastBillsOfTheMonth() : Routes.bills();
            const sessionParam =
                listMode === "all_bills" && legislativeSessionId !== null
                    ? `&bills_legislative_session_id=${legislativeSessionId}`
                    : "";
            return `${basePath}?sway_locale_id=${swayLocaleId}&page=${pageNum}${sessionParam}`;
        },
        [listMode, legislativeSessionId, swayLocaleId],
    );

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(null);
        setPageError(null);
        pageRef.current = 1;
        setPage(1);
        const currentGen = generationRef.current;
        try {
            if (isDefaultAllBills) {
                const cached = await billCache.get(swayLocaleId);
                if (mountedRef.current && generationRef.current === currentGen && cached.length) {
                    setData(cached.map((r) => r.bill as BillRecord));
                }
            }
            if (reach.isOnline) {
                const fetchPromise = apiClient.get<BillsApiResponse>(buildBillsPath(1));
                inFlightBillsRequests[swayLocaleId] = fetchPromise;
                let res: BillsApiResponse;
                try {
                    res = await fetchPromise;
                } finally {
                    if (inFlightBillsRequests[swayLocaleId] === fetchPromise) {
                        delete inFlightBillsRequests[swayLocaleId];
                    }
                }
                if (!mountedRef.current || generationRef.current !== currentGen) return;
                const freshBills = res.bills ?? [];
                if (isDefaultAllBills) {
                    await billCache.set(swayLocaleId, freshBills);
                    if (!mountedRef.current || generationRef.current !== currentGen) return;
                }
                setData(freshBills);
                const total = res.bills_total ?? freshBills.length;
                setBillsTotal(total);
                const cats = res.all_categories ?? [];
                capturedCategoriesByLocale[swayLocaleId] = cats;
                setAllCategories(cats);
                if (res.legislative_sessions && listMode === "all_bills") {
                    capturedSessionsByLocale[swayLocaleId] = res.legislative_sessions;
                    setLegislativeSessions(res.legislative_sessions);
                }
                if (res.selected_legislative_session_id !== undefined) {
                    setSelectedLegislativeSessionId(res.selected_legislative_session_id);
                }
            }
        } catch (e: unknown) {
            if (mountedRef.current && generationRef.current === currentGen) {
                setError(e instanceof Error ? e : new Error(String(e)));
            }
        } finally {
            if (mountedRef.current && generationRef.current === currentGen) {
                setLoading(false);
            }
        }
    }, [swayLocaleId, reach.isOnline, isDefaultAllBills, listMode, buildBillsPath]);

    useEffect(() => {
        if (!enabled) return;
        mountedRef.current = true;
        generationRef.current += 1;
        pageRef.current = 1;
        loadingMoreRef.current = false;
        setLoadingMore(false);
        setPage(1);
        setPageError(null);
        setError(null);
        setData(null);
        setBillsTotal(0);
        setAllCategories(capturedCategoriesByLocale[swayLocaleId] ?? []);
        setLegislativeSessions(capturedSessionsByLocale[swayLocaleId] ?? []);
        setSelectedLegislativeSessionId(legislativeSessionId);

        void refresh();

        return () => {
            mountedRef.current = false;
        };
    }, [swayLocaleId, listMode, legislativeSessionId, refresh, enabled]);

    const wasOnlineRef = useRef<boolean>(reach.isOnline);
    useEffect(() => {
        if (!enabled) return;
        const wasOnline = wasOnlineRef.current;
        wasOnlineRef.current = reach.isOnline;
        if (!wasOnline && reach.isOnline) {
            void refresh();
        }
    }, [reach.isOnline, refresh, enabled]);

    const loadMore = useCallback(async () => {
        if (loadingMoreRef.current || loading || !hasMore || !reach.isOnline) return;
        loadingMoreRef.current = true;
        setLoadingMore(true);
        setPageError(null);
        const nextPage = pageRef.current + 1;
        const currentGen = generationRef.current;
        try {
            const res = await apiClient.get<BillsApiResponse>(buildBillsPath(nextPage));
            if (!mountedRef.current || generationRef.current !== currentGen) return;
            pageRef.current = nextPage;
            setPage(nextPage);
            setData(res.bills ?? []);
            setBillsTotal(res.bills_total ?? res.bills?.length ?? 0);
            if (res.all_categories) {
                capturedCategoriesByLocale[swayLocaleId] = res.all_categories;
                setAllCategories(res.all_categories);
            }
            if (res.legislative_sessions && listMode === "all_bills") {
                capturedSessionsByLocale[swayLocaleId] = res.legislative_sessions;
                setLegislativeSessions(res.legislative_sessions);
            }
            if (res.selected_legislative_session_id !== undefined) {
                setSelectedLegislativeSessionId(res.selected_legislative_session_id);
            }
        } catch (err) {
            if (mountedRef.current && generationRef.current === currentGen) {
                setPageError(err instanceof Error ? err : new Error(String(err)));
            }
        } finally {
            loadingMoreRef.current = false;
            if (mountedRef.current && generationRef.current === currentGen) {
                setLoadingMore(false);
            }
        }
    }, [swayLocaleId, loading, hasMore, reach.isOnline, listMode, buildBillsPath]);

    return {
        data,
        loading,
        error,
        refresh,
        isOnline: reach.isOnline,
        isResolved: reach.isResolved,
        page,
        billsTotal,
        allCategories,
        legislativeSessions,
        selectedLegislativeSessionId,
        loadingMore,
        pageError,
        hasMore,
        loadMore,
    };
}

// @lat: [[mobile-bill-hooks#useBillCategories]]
export function useBillCategories(swayLocaleId: number): { allCategories: string[] } {
    const [allCategories, setAllCategories] = useState<string[]>(() => capturedCategoriesByLocale[swayLocaleId] ?? []);

    useEffect(() => {
        if (!swayLocaleId) {
            setAllCategories([]);
            return;
        }
        if (capturedCategoriesByLocale[swayLocaleId]) {
            setAllCategories(capturedCategoriesByLocale[swayLocaleId]);
            return;
        }
        let cancelled = false;

        if (inFlightBillsRequests[swayLocaleId]) {
            void inFlightBillsRequests[swayLocaleId]
                .then((res) => {
                    const cats = res.all_categories ?? [];
                    if (!cancelled) setAllCategories(cats);
                })
                .catch(() => {});
            return () => {
                cancelled = true;
            };
        }

        void apiClient
            .get<{ all_categories?: string[] }>(`${Routes.bills()}?sway_locale_id=${swayLocaleId}`)
            .then((res) => {
                if (!cancelled) setAllCategories(res.all_categories ?? []);
            })
            .catch(() => {});
        return () => {
            cancelled = true;
        };
    }, [swayLocaleId]);

    return { allCategories };
}
