import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import type { IFeedItem } from "../components/feed/types";
import { useReachability } from "./useReachability";

export interface FeedApiResponse {
    items?: IFeedItem[];
    feed_cursor?: string | null;
    feed_search?: string | null;
}

export interface UseFeedResult {
    items: IFeedItem[];
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
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const [nextCursor, setNextCursor] = useState<string | null>(null);
    const [loadingMore, setLoadingMore] = useState<boolean>(false);
    const [pageError, setPageError] = useState<Error | null>(null);

    const reach = useReachability();
    const mountedRef = useRef<boolean>(true);
    const loadingMoreRef = useRef<boolean>(false);
    const generationRef = useRef<number>(0);

    const refresh = useCallback(async () => {
        generationRef.current += 1;
        const currentGen = generationRef.current;
        setLoading(true);
        setError(null);
        setPageError(null);
        setNextCursor(null);
        loadingMoreRef.current = false;
        setLoadingMore(false);

        if (!reach.isOnline) {
            if (mountedRef.current && generationRef.current === currentGen) {
                setLoading(false);
            }
            return;
        }

        try {
            const res = await apiClient.get<FeedApiResponse>(buildFeedPath(trimmedQuery));
            if (!mountedRef.current || generationRef.current !== currentGen) return;
            setItems(res.items ?? []);
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
    }, [reach.isOnline, trimmedQuery]);

    useEffect(() => {
        mountedRef.current = true;
        void refresh();
        return () => {
            mountedRef.current = false;
        };
    }, [refresh]);

    const wasOnlineRef = useRef<boolean>(reach.isOnline);
    useEffect(() => {
        const wasOnline = wasOnlineRef.current;
        wasOnlineRef.current = reach.isOnline;
        if (!wasOnline && reach.isOnline) {
            void refresh();
        }
    }, [reach.isOnline, refresh]);

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
            loadingMoreRef.current = false;
            if (mountedRef.current && generationRef.current === currentGen) {
                setLoadingMore(false);
            }
        }
    }, [loading, nextCursor, reach.isOnline, trimmedQuery]);

    return {
        items,
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
