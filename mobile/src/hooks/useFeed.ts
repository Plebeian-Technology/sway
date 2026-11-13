import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import type { IFeedItem } from "../components/feed/types";
import { useReachability } from "./useReachability";

export interface FeedApiResponse {
    items?: IFeedItem[];
    feed_cursor?: string | null;
    feed_search?: string | null;
    feed_match_count?: number;
}

export interface UseFeedResult {
    items: IFeedItem[];
    matchCount: number;
    loading: boolean;
    error: Error | null;
    loadingMore: boolean;
    pageError: Error | null;
    hasMore: boolean;
    isOnline: boolean;
    isResolved: boolean;
    refresh: () => Promise<void>;
    loadMore: () => Promise<void>;
}

const buildFeedPath = (searchQuery: string, cursor?: string | null): string => {
    const base = Routes.feed();
    const params: string[] = [];
    if (searchQuery.length > 0) {
        params.push(`feed_search=${encodeURIComponent(searchQuery)}`);
    }
    if (cursor) {
        params.push(`feed_cursor=${encodeURIComponent(cursor)}`);
    }
    return params.length > 0 ? `${base}?${params.join("&")}` : base;
};

export function useFeed(searchQuery = ""): UseFeedResult {
    const trimmedQuery = searchQuery.trim();
    const [items, setItems] = useState<IFeedItem[]>([]);
    const [matchCount, setMatchCount] = useState<number>(0);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const [nextCursor, setNextCursor] = useState<string | null>(null);
    const [loadingMore, setLoadingMore] = useState<boolean>(false);
    const [pageError, setPageError] = useState<Error | null>(null);
    const [prevQuery, setPrevQuery] = useState<string>(trimmedQuery);

    if (trimmedQuery !== prevQuery) {
        setPrevQuery(trimmedQuery);
        setItems([]);
        setMatchCount(0);
        setNextCursor(null);
        setLoading(true);
        setError(null);
        setPageError(null);
    }

    const reach = useReachability();
    const mountedRef = useRef<boolean>(true);
    const loadingMoreRef = useRef<boolean>(false);
    const generationRef = useRef<number>(0);

    useEffect(() => {
        mountedRef.current = true;
        return () => {
            mountedRef.current = false;
        };
    }, []);

    const refresh = useCallback(async () => {
        generationRef.current += 1;
        const currentGen = generationRef.current;

        setError(null);
        setPageError(null);
        loadingMoreRef.current = false;
        setLoadingMore(false);

        if (!reach.isResolved && !reach.isOnline) {
            setLoading(true);
            return;
        }

        if (!reach.isOnline) {
            if (mountedRef.current && generationRef.current === currentGen) {
                setLoading(false);
            }
            return;
        }

        setLoading(true);

        try {
            const res = await apiClient.get<FeedApiResponse>(buildFeedPath(trimmedQuery));
            if (!mountedRef.current || generationRef.current !== currentGen) return;
            const nextItems = res.items ?? [];
            setItems(nextItems);
            setMatchCount(res.feed_match_count ?? 0);
            setNextCursor(res.feed_cursor ?? null);
        } catch (err) {
            if (mountedRef.current && generationRef.current === currentGen) {
                setError(err instanceof Error ? err : new Error(String(err)));
            }
        } finally {
            if (mountedRef.current && generationRef.current === currentGen) {
                setLoading(false);
            }
        }
    }, [reach.isOnline, reach.isResolved, trimmedQuery]);

    useEffect(() => {
        void refresh();
    }, [refresh]);

    const loadMore = useCallback(async () => {
        if (loadingMoreRef.current || loading || nextCursor === null || !reach.isOnline) return;
        loadingMoreRef.current = true;
        setLoadingMore(true);
        setPageError(null);
        const currentGen = generationRef.current;

        try {
            const res = await apiClient.get<FeedApiResponse>(buildFeedPath(trimmedQuery, nextCursor));
            if (!mountedRef.current || generationRef.current !== currentGen) return;
            const incoming = res.items ?? [];
            setItems((prev) => {
                const seen = new Set(prev.map((item) => item.key));
                const merged = [...prev];
                for (const item of incoming) {
                    if (!seen.has(item.key)) {
                        seen.add(item.key);
                        merged.push(item);
                    }
                }
                return merged;
            });
            setNextCursor(res.feed_cursor ?? null);
        } catch (err) {
            if (mountedRef.current && generationRef.current === currentGen) {
                setPageError(err instanceof Error ? err : new Error(String(err)));
            }
        } finally {
            if (generationRef.current === currentGen) {
                loadingMoreRef.current = false;
                if (mountedRef.current) {
                    setLoadingMore(false);
                }
            }
        }
    }, [loading, nextCursor, reach.isOnline, trimmedQuery]);

    return {
        items,
        matchCount,
        loading,
        error,
        loadingMore,
        pageError,
        hasMore: nextCursor !== null,
        isOnline: reach.isOnline,
        isResolved: reach.isResolved,
        refresh,
        loadMore,
    };
}
