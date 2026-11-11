// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import { useCallback, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { useMembershipResource } from "./useMembershipResource";

export interface PendingChangeRecord {
    id: number;
    organization_bill_position_id: number;
    previous_support: string;
    new_support: string;
    previous_summary: string;
    new_summary: string;
    created_at: string;
    approved_by_id: number | null;
    rejected_by_id?: number | null;
    rejected_at?: string | null;
    status?: "pending" | "approved" | "rejected";
    bill?: {
        id: number;
        external_id?: string;
        title?: string;
    } | null;
}

interface MembershipChangesPayload {
    membership?: {
        pending_changes?: PendingChangeRecord[];
    };
}

export interface UsePendingChangesResult {
    changes: PendingChangeRecord[];
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
    approve: (id: number) => Promise<void>;
    reject: (id: number) => Promise<void>;
    busy: boolean;
}

const extractChanges = (res: MembershipChangesPayload | undefined) => res?.membership?.pending_changes;

export interface UsePendingChangesOptions {
    enabled?: boolean;
}

export function usePendingChanges(
    orgId: number,
    membershipId: number,
    options?: UsePendingChangesOptions,
): UsePendingChangesResult {
    const {
        data: changes,
        loading,
        error,
        refresh,
    } = useMembershipResource<PendingChangeRecord, MembershipChangesPayload>(
        orgId,
        membershipId,
        extractChanges,
        options,
    );
    const [busy, setBusy] = useState(false);
    const enabled = options?.enabled;

    const approve = useCallback(
        async (id: number) => {
            setBusy(true);
            try {
                await apiClient.patch(Routes.pendingChange(orgId, id), undefined);
                if (enabled !== false) {
                    await refresh();
                }
            } finally {
                setBusy(false);
            }
        },
        [orgId, refresh, enabled],
    );

    const reject = useCallback(
        async (id: number) => {
            setBusy(true);
            try {
                await apiClient.delete(Routes.pendingChange(orgId, id));
                if (enabled !== false) {
                    await refresh();
                }
            } finally {
                setBusy(false);
            }
        },
        [orgId, refresh, enabled],
    );

    return { changes, loading, error, refresh, approve, reject, busy };
}
