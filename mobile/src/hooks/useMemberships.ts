// @lat: [[mobile-membership-hooks#useMemberships]]
import { useCallback, useEffect, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";

export type MembershipOrganization = {
    id: number;
    name: string;
    member_count?: number;
} & Record<string, unknown>;

export type MembershipRecord = {
    id: number;
    role: "admin" | "standard";
    organization?: MembershipOrganization;
} & Record<string, unknown>;

interface MembershipsResponse {
    memberships?: MembershipRecord[];
    pending_memberships?: MembershipRecord[];
}

export interface UseMembershipsResult {
    active: MembershipRecord[];
    pending: MembershipRecord[];
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useMemberships(): UseMembershipsResult {
    const [active, setActive] = useState<MembershipRecord[]>([]);
    const [pending, setPending] = useState<MembershipRecord[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);

    const refresh = useCallback(async () => {
        setLoading(true);
        try {
            const res = await apiClient.get<MembershipsResponse>(Routes.memberships());
            setActive(res.memberships ?? []);
            setPending(res.pending_memberships ?? []);
            setError(null);
        } catch (e: unknown) {
            if (e instanceof ApiRequestError && e.code === "aborted") return;
            setError(e instanceof Error ? e : new Error(String(e)));
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        void refresh();
    }, [refresh]);

    return { active, pending, loading, error, refresh };
}
