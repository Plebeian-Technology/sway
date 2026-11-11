// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import { useCallback, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { useMembershipResource } from "./useMembershipResource";

export interface OrgPositionRecord {
    id: number;
    support: string;
    summary: string;
    link?: string | null;
    active?: boolean;
    bill?: {
        id: number;
        external_id?: string;
        title?: string;
    } | null;
    bill_id?: number;
}

interface MembershipPositionsPayload {
    membership?: {
        positions?: OrgPositionRecord[];
    };
}

export interface ProposePositionPayload {
    bill_id: number;
    support: "FOR" | "AGAINST";
    summary: string;
    source_url?: string;
}

export interface UseOrganizationPositionsResult {
    positions: OrgPositionRecord[];
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
    propose: (payload: ProposePositionPayload) => Promise<void>;
    busy: boolean;
}

const extractPositions = (res: MembershipPositionsPayload | undefined) => res?.membership?.positions;

export interface UseOrganizationPositionsOptions {
    enabled?: boolean;
}

export function useOrganizationPositions(
    orgId: number,
    membershipId: number,
    options?: UseOrganizationPositionsOptions,
): UseOrganizationPositionsResult {
    const {
        data: positions,
        loading,
        error,
        refresh,
    } = useMembershipResource<OrgPositionRecord, MembershipPositionsPayload>(
        orgId,
        membershipId,
        extractPositions,
        options,
    );
    const [busy, setBusy] = useState(false);
    const enabled = options?.enabled;

    const propose = useCallback(
        async (payload: ProposePositionPayload) => {
            setBusy(true);
            try {
                await apiClient.post(Routes.orgPositions(orgId), payload);
                if (enabled !== false) {
                    await refresh();
                }
            } finally {
                setBusy(false);
            }
        },
        [orgId, refresh, enabled],
    );

    return { positions, loading, error, refresh, propose, busy };
}
