// @lat: [[mobile-admin-area#The shared addresses screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface SharedAddressRow {
    address_ids: number[];
    user_count: number;
}

export interface UseSharedAddressesResult {
    sharedAddresses: SharedAddressRow[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useSharedAddresses(): UseSharedAddressesResult {
    const [sharedAddresses, setSharedAddresses] = useState<SharedAddressRow[] | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<{ shared_addresses: SharedAddressRow[] }>(Routes.adminSharedAddresses(), {
                signal: ctrl.signal,
            });
            if (ctrl.signal.aborted) return;
            setSharedAddresses(res.shared_addresses);
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

    return { sharedAddresses, loading, error, refresh };
}
