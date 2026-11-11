// @lat: [[mobile-offline-cache-hook#The cycle]]
import { useCallback, useEffect, useState, useRef } from "react";
import { useReachability } from "./useReachability";
import { logDev } from "@/utils/logging";

export interface CacheAdapter<T> {
    get: () => Promise<T[]>;
    set: (data: T[]) => Promise<void>;
}

export interface UseOfflineCacheOptions<T> {
    cache: CacheAdapter<T>;
    fetcher: () => Promise<T[]>;
    deps?: readonly unknown[];
    name?: string;
}

export interface UseOfflineCacheResult<T> {
    data: T[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
    isOnline: boolean;
    // @lat: [[mobile-offline-cache-hook#isResolved]]
    isResolved: boolean;
}

export function useOfflineCache<T>({
    name,
    cache,
    fetcher,
    deps = [],
}: UseOfflineCacheOptions<T>): UseOfflineCacheResult<T> {
    // @lat: [[mobile-offline-cache-hook#Internal state notes]]
    const [data, setData] = useState<T[] | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const reach = useReachability();
    const mountedRef = useRef<boolean>(true);

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const cached = await cache.get();
            if (mountedRef.current && cached.length) setData(cached);
            if (reach.isOnline) {
                const fresh = await fetcher();
                await cache.set(fresh);
                if (mountedRef.current) setData(fresh);
            }
        } catch (e: unknown) {
            if (mountedRef.current) {
                setError(e instanceof Error ? e : new Error(String(e)));
            }
        } finally {
            if (mountedRef.current) setLoading(false);
        }
    }, [cache, fetcher, reach.isOnline]);

    useEffect(() => {
        mountedRef.current = true;
        refresh()
            .then(() => {
                logDev("useOfflineCache refresh complete", {
                    name,
                    data: !!data?.length,
                    error,
                    isOnline: reach.isOnline,
                });
            })
            .catch(console.error);
        return () => {
            mountedRef.current = false;
        };
        // oxlint-disable-next-line react-hooks/exhaustive-deps
    }, deps);

    // @lat: [[mobile-offline-cache-hook#The cycle]]
    const wasOnlineRef = useRef<boolean>(reach.isOnline);
    useEffect(() => {
        const wasOnline = wasOnlineRef.current;
        wasOnlineRef.current = reach.isOnline;
        if (!wasOnline && reach.isOnline) {
            refresh().catch(console.error);
        }
    }, [reach.isOnline, refresh]);

    return { data, loading, error, refresh, isOnline: reach.isOnline, isResolved: reach.isResolved };
}

// @lat: [[mobile-offline-cache-hook#Writes must check isOnline first]]
export function assertOnlineForWrite(isOnline: boolean): void {
    if (!isOnline) throw new Error("offline_write_blocked");
}
