// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import { useCallback, useEffect, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { ApiRequestError } from "../api/errors";
import type { OrgPositionDisplay } from "../components/PositionCard";
import type { OrgMemberRecord } from "../components/MembersList";
import type { PendingChangeRecord } from "./usePendingChanges";

export type MembershipPayload = {
    membership?: {
        id: number;
        user_id?: number;
        role: "admin" | "standard";
        organization?: {
            id: number;
            name: string;
            member_count?: number;
            sway_locale_id?: number;
        } & Record<string, unknown>;
        positions?: OrgPositionDisplay[];
        pending_changes?: PendingChangeRecord[];
        members?: OrgMemberRecord[];
    } & Record<string, unknown>;
} & Record<string, unknown>;

export interface UseMembershipResult {
    data: MembershipPayload | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
}

export function useMembership(orgId: number, id: number): UseMembershipResult {
    const [data, setData] = useState<MembershipPayload | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);

    const refresh = useCallback(async () => {
        setLoading(true);
        try {
            const res = await apiClient.get<MembershipPayload>(Routes.membership(orgId, id));
            setData(res);
            setError(null);
        } catch (e: unknown) {
            if (e instanceof ApiRequestError && e.code === "aborted") return;
            const err = e instanceof Error ? e : new Error(String(e));
            setError(err);
            throw err;
        } finally {
            setLoading(false);
        }
    }, [orgId, id]);

    useEffect(() => {
        refresh().catch(() => {});
    }, [refresh]);

    return { data, loading, error, refresh };
}
