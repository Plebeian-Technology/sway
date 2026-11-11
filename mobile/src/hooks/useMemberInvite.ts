// @lat: [[membership-invite-accept-flow#useMemberInvite, the mobile hook]]
import { useCallback, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";

export interface UseMemberInviteResult {
    invite: (orgId: number, email: string) => Promise<void>;
    busy: boolean;
    error: Error | null;
}

export function useMemberInvite(): UseMemberInviteResult {
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<Error | null>(null);

    const invite = useCallback(async (orgId: number, email: string) => {
        setBusy(true);
        setError(null);
        try {
            await apiClient.post(Routes.membershipInvites(orgId), {
                invite: { invitee_email: email },
            });
        } catch (e: unknown) {
            setError(e instanceof Error ? e : new Error(String(e)));
            throw e;
        } finally {
            setBusy(false);
        }
    }, []);

    return { invite, busy, error };
}
