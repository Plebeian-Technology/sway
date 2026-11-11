import { useCallback, useEffect, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";

// @lat: [[mobile-membership-state#Hidden modal query suppression]]
export function useMembershipResource<T, P>(
    orgId: number,
    membershipId: number,
    extract: (payload: P | undefined) => T[] | undefined,
    options?: { enabled?: boolean },
) {
    const enabled = options?.enabled ?? true;
    const [data, setData] = useState<T[]>([]);
    const [loading, setLoading] = useState(enabled);
    const [error, setError] = useState<Error | null>(null);

    const refresh = useCallback(async () => {
        setLoading(true);
        try {
            const res = await apiClient.get<P>(Routes.membership(orgId, membershipId));
            setData(extract(res) ?? []);
            setError(null);
        } catch (e: unknown) {
            if (e instanceof ApiRequestError && e.code === "aborted") return;
            setError(e instanceof Error ? e : new Error(String(e)));
        } finally {
            setLoading(false);
        }
    }, [orgId, membershipId, extract]);

    useEffect(() => {
        if (!enabled) return;
        void refresh();
    }, [refresh, enabled]);

    return { data, setData, loading, error, refresh };
}
