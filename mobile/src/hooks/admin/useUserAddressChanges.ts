// @lat: [[mobile-admin-area#The user address changes screen]]
import { useCallback, useEffect, useRef, useState } from "react";

import { apiClient } from "../../api/client";
import { Routes } from "../../api/routes";
import { ApiRequestError } from "../../api/errors";

export interface UserAddressChangeRow {
    id: number;
    user_id: number;
    previous_address_id: number;
    new_address_id: number;
    deactivated_legislator_ids: number[];
    activated_legislator_ids: number[];
    deactivated_district_ids: number[];
    activated_district_ids: number[];
    previous_sway_locale_ids: number[];
    new_sway_locale_ids: number[];
    previous_sway_locale_names: string[];
    new_sway_locale_names: string[];
    prior_vote_count: number;
    prior_voted_bill_ids: number[];
    prior_voted_sway_locale_ids: number[];
    cross_district: boolean;
    cross_sway_locale: boolean;
    voted_before_switch: boolean;
    user_switch_count: number;
    created_at: string;
}

export interface UseUserAddressChangesResult {
    userAddressChanges: UserAddressChangeRow[] | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useUserAddressChanges(): UseUserAddressChangesResult {
    const [userAddressChanges, setUserAddressChanges] = useState<UserAddressChangeRow[] | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const abortRef = useRef<AbortController | null>(null);

    const refresh = useCallback(async () => {
        abortRef.current?.abort();
        const ctrl = new AbortController();
        abortRef.current = ctrl;
        setLoading(true);
        try {
            const res = await apiClient.get<{ user_address_changes: UserAddressChangeRow[] }>(
                Routes.adminUserAddressChanges(),
                {
                    signal: ctrl.signal,
                },
            );
            if (ctrl.signal.aborted) return;
            setUserAddressChanges(res.user_address_changes);
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

    return { userAddressChanges, loading, error, refresh };
}
