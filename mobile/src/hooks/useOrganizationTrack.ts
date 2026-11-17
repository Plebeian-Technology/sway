// @lat: [[mobile-organization-follow-hook#The followId sentinel]]
import { useCallback, useState } from "react";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";

export interface OrgFollowPrefs {
    notify_on_new_position?: boolean;
    notify_on_support_change?: boolean;
    notify_on_summary_change?: boolean;
    notification_cadence?: "every_change" | "daily" | "weekly";
}

export interface UseOrganizationTrackResult {
    // @lat: [[mobile-organization-follow-hook#The followId sentinel]]
    followId: number | null;
    follow: () => Promise<void>;
    unfollow: () => Promise<void>;
    // @lat: [[mobile-organization-follow-hook#The followId sentinel]]
    updatePreferences: (prefs: OrgFollowPrefs) => Promise<void>;
    // @lat: [[mobile-organization-follow-hook#createFollowWithPrefs]]
    createFollowWithPrefs: (prefs: OrgFollowPrefs) => Promise<void>;
}

// @lat: [[mobile-organization-follow-hook#@param initialFollowId]]
export function useOrganizationTrack(
    orgId: number,
    initialFollowId: number | null = null,
): UseOrganizationTrackResult {
    const [followId, setFollowId] = useState<number | null>(initialFollowId);

    const follow = useCallback(async () => {
        // @lat: [[mobile-organization-follow-hook#The followId sentinel]]
        const prevId = followId;
        setFollowId(-1);
        try {
            await apiClient.post(Routes.organizationTracks(), { organization_id: orgId });
            try {
                const orgData = await apiClient.get<{ current_user_follow_id?: number }>(
                    `/public/organizations/${orgId}`,
                );
                setFollowId(orgData.current_user_follow_id ?? -1);
            } catch {
                // @lat: [[mobile-organization-follow-hook#follow()]]
            }
        } catch (err) {
            setFollowId(prevId);
            throw err;
        }
    }, [orgId, followId]);

    const unfollow = useCallback(async () => {
        const prevId = followId;
        if (prevId === -1) {
            // @lat: [[mobile-organization-follow-hook#unfollow()]]
            throw new Error("Follow ID not yet resolved. Please wait and try again.");
        }
        setFollowId(null);
        try {
            if (prevId != null && prevId > 0) {
                await apiClient.delete(Routes.organizationTrack(prevId));
            }
        } catch (err) {
            setFollowId(prevId);
            throw err;
        }
    }, [followId]);

    const updatePreferences = useCallback(
        async (prefs: OrgFollowPrefs) => {
            if (followId === null) {
                return;
            }
            if (followId === -1) {
                throw new Error("Follow not yet resolved. Please wait and try again.");
            }
            await apiClient.patch(Routes.organizationTrackPreferences(followId), {
                organization_track: prefs,
            });
        },
        [followId],
    );

    const createFollowWithPrefs = useCallback(
        async (prefs: OrgFollowPrefs) => {
            await apiClient.post(Routes.organizationTracks(), {
                organization_id: orgId,
                organization_track: prefs,
            });
            try {
                const orgData = await apiClient.get<{ current_user_follow_id?: number }>(
                    `/public/organizations/${orgId}`,
                );
                setFollowId(orgData.current_user_follow_id ?? -1);
            } catch {
                setFollowId(-1);
            }
        },
        [orgId],
    );

    return { followId, follow, unfollow, updatePreferences, createFollowWithPrefs };
}
