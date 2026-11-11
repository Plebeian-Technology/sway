// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import { useCallback, useRef, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";

export class InviteRefreshError extends Error {
    constructor(
        message: string,
        public readonly cause?: unknown,
    ) {
        super(message);
        this.name = "InviteRefreshError";
    }
}

interface UseInviteAcceptOptions {
    refresh?: () => Promise<void>;
}

interface UseInviteAcceptResult {
    accept: (orgId: number, id: number) => Promise<void>;
    decline: (orgId: number, id: number) => Promise<void>;
    error: Error | null;
}

export function useInviteAccept({ refresh }: UseInviteAcceptOptions): UseInviteAcceptResult {
    const [error, setError] = useState<Error | null>(null);
    const inFlightRef = useRef<Set<number>>(new Set());

    const accept = useCallback(
        async (orgId: number, id: number) => {
            inFlightRef.current.add(id);
            setError(null);
            let didAccept = false;
            try {
                await apiClient.post(Routes.acceptInvite(orgId, id), undefined);
                didAccept = true;
                if (refresh) await refresh();
            } catch (err) {
                const e = err instanceof Error ? err : new Error(String(err));
                if (didAccept) {
                    throw new InviteRefreshError(e.message, e);
                }
                setError(e);
                throw e;
            } finally {
                inFlightRef.current.delete(id);
            }
        },
        [refresh],
    );

    const decline = useCallback(
        async (orgId: number, id: number) => {
            inFlightRef.current.add(id);
            setError(null);
            let didDecline = false;
            try {
                await apiClient.delete(Routes.declineInvite(orgId, id));
                didDecline = true;
                if (refresh) await refresh();
            } catch (err) {
                const e = err instanceof Error ? err : new Error(String(err));
                if (didDecline) {
                    throw new InviteRefreshError(e.message, e);
                }
                setError(e);
                throw e;
            } finally {
                inFlightRef.current.delete(id);
            }
        },
        [refresh],
    );

    return { accept, decline, error };
}
