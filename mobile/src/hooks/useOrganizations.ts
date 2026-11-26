// @lat: [[mobile-organizations-hook#Payload fields]]
import { useCallback, useEffect, useState } from "react";

import { apiClient } from "../api/client";

export interface OrganizationRecord {
    id: number;
    name: string;
    icon_url?: string | null;
    sway_locale_id?: number;
    sway_locale_slug?: string | null;
    created_at?: string;
    managed_on_sway: boolean;
}

// @lat: [[mobile-organizations-hook#Payload fields]]
export interface OrgFollowPref {
    follow_id: number;
    notify_on_new_position: boolean;
    notify_on_support_change: boolean;
    notify_on_summary_change: boolean;
    notification_cadence: "every_change" | "daily" | "weekly";
    muted: boolean;
}

// @lat: [[mobile-organizations-hook#Payload fields]]
export interface OrgDefaultPrefs {
    notify_on_new_position: boolean;
    notify_on_support_change: boolean;
    notify_on_summary_change: boolean;
    notification_cadence: "every_change" | "daily" | "weekly";
}

export interface OrganizationsPayload {
    organizations: OrganizationRecord[];
    applied_filters?: { locale_id?: string | null };
    // @lat: [[mobile-organizations-hook#Payload fields]]
    user_follows?: Record<number, number>;
    is_member_of_org_ids?: number[];
    user_follow_prefs?: Record<number, OrgFollowPref>;
    current_user_org_defaults?: OrgDefaultPrefs;
}

export interface OrgFilters {
    swayLocaleId?: number;
}

export interface UseOrganizationsResult {
    data: OrganizationsPayload | null;
    loading: boolean;
    error: Error | null;
    refresh: () => Promise<void>;
    isOnline: boolean;
}

export function useOrganizations(filters: OrgFilters = {}): UseOrganizationsResult {
    const [data, setData] = useState<OrganizationsPayload | null>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<Error | null>(null);
    const [isOnline, setIsOnline] = useState<boolean>(true);

    const refresh = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const qs = new URLSearchParams();
            if (filters.swayLocaleId != null) qs.set("locale_id", String(filters.swayLocaleId));
            const path = `/public/organizations${qs.toString() ? `?${qs.toString()}` : ""}`;
            const payload = await apiClient.get<OrganizationsPayload>(path);
            setData(payload);
            setIsOnline(true);
        } catch (e: unknown) {
            setError(e instanceof Error ? e : new Error(String(e)));
            setIsOnline(false);
        } finally {
            setLoading(false);
        }
    }, [filters.swayLocaleId]);

    useEffect(() => {
        void refresh();
    }, [refresh]);

    return { data, loading, error, refresh, isOnline };
}
