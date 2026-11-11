// @lat: [[user-vote-submission#Submission hooks]]
import { useCallback } from "react";

import { useReachability } from "./useReachability";
import { assertOnlineForWrite } from "./useOfflineCache";
import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import * as billCache from "../cache/billCache";
import * as voteCache from "../cache/voteCache";
import * as legislatorCache from "../cache/legislatorCache";

export type VoteSupport = "for" | "against";

export interface VoteResponse {
    redirect?: string;
    flash?: string;
}

export interface UseCastUserVoteResult {
    submit: (billId: number, support: VoteSupport) => Promise<VoteResponse>;
    isOnline: boolean;
    // @lat: [[mobile-offline-cache-hook#isResolved]]
    isResolved: boolean;
}

export function useCastUserVote(): UseCastUserVoteResult {
    const reach = useReachability();

    const submit = useCallback(
        async (billId: number, support: VoteSupport): Promise<VoteResponse> => {
            assertOnlineForWrite(reach.isOnline);
            // @lat: [[user-vote-submission#Submission hooks]]
            const res = await apiClient.post<VoteResponse>(Routes.userVotes(), {
                bill_id: billId,
                support: support.toUpperCase(),
            });
            await voteCache.set(billId, {
                bill_id: billId,
                support,
                created_at: Date.now(),
            });
            await billCache.clearOne(billId);
            // @lat: [[mobile-sqlite-cache-design#Why vote submission evicts the target bill's locale cache]]
            await legislatorCache.clear().catch(() => {});
            return res ?? {};
        },
        [reach.isOnline],
    );

    return { submit, isOnline: reach.isOnline, isResolved: reach.isResolved };
}
