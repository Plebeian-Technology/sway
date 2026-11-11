// @lat: [[mobile-user-profile-hook#Why not read the startup payload directly?]]
import { useBootstrap } from "../state/BootstrapContext";

export interface UserProfile {
    id: number;
    full_name?: string | null;
    email?: string | null;
    phone?: string | null;
    is_registration_complete?: boolean;
    is_registered_to_vote?: boolean;
    sms_notifications_enabled?: boolean;
    theme_mode?: "auto" | "light" | "dark" | null;
    address?: {
        street1?: string | null;
        street2?: string | null;
        city?: string | null;
        region_code?: string | null;
        postal_code?: string | null;
        country?: string | null;
    } | null;
}

export interface UseUserProfileResult {
    user: UserProfile | null;
    loading: boolean;
    refresh: () => Promise<void>;
}

export function useUserProfile(): UseUserProfileResult {
    const { bootstrap, loading, refetch } = useBootstrap();
    const cu = bootstrap?.current_user as (UserProfile & { address?: UserProfile["address"] }) | null | undefined;
    return {
        user: cu ?? null,
        loading,
        refresh: refetch,
    };
}
