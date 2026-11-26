import { useCallback, useState } from "react";
import { OrgFollowPrefs, useOrganizationFollow } from "./useOrganizationFollow";

export interface UseOrgFollowSheetOptions {
    orgId: number;
    initialFollowId?: number | null;
    isMember?: boolean;
    isSignedIn?: boolean;
    initialPrefs?: OrgFollowPrefs;
    defaultPrefs?: OrgFollowPrefs;
    orgName?: string;
    onFollowSuccess?: () => void;
    onUnfollowSuccess?: () => void;
    onRequireSignIn?: () => void;
}

export function useOrgFollowSheet({
    orgId,
    initialFollowId = null,
    isMember = false,
    isSignedIn = true,
    initialPrefs,
    defaultPrefs,
    orgName,
    onFollowSuccess,
    onUnfollowSuccess,
    onRequireSignIn,
}: UseOrgFollowSheetOptions) {
    const { followId, follow, unfollow, updatePreferences, createFollowWithPrefs } = useOrganizationFollow(
        orgId,
        initialFollowId ?? null,
    );

    const [showPrefSheet, setShowPrefSheet] = useState<boolean>(false);
    const [prefSheetOpenNonce, setPrefSheetOpenNonce] = useState<number>(0);
    const [isFirstFollow, setIsFirstFollow] = useState<boolean>(false);
    const [followError, setFollowError] = useState<string | null>(null);

    const isFollowing = followId !== null;

    const [lastSavedPrefs, setLastSavedPrefs] = useState<OrgFollowPrefs | undefined>(undefined);
    const currentInitialPrefs: OrgFollowPrefs | undefined = lastSavedPrefs ?? initialPrefs ?? defaultPrefs;

    const handlePrefsSave = useCallback(
        async (prefs: OrgFollowPrefs) => {
            if (isMember && followId === null) {
                await createFollowWithPrefs(prefs);
            } else {
                await updatePreferences(prefs);
            }
            setLastSavedPrefs(prefs);
        },
        [isMember, followId, createFollowWithPrefs, updatePreferences],
    );

    const handleFollowPress = useCallback(async () => {
        if (!isSignedIn) {
            onRequireSignIn?.();
            return;
        }
        setFollowError(null);
        try {
            await follow();
            onFollowSuccess?.();
            setIsFirstFollow(true);
            setPrefSheetOpenNonce((n) => n + 1);
            setShowPrefSheet(true);
        } catch {
            const nameMsg = orgName ? ` ${orgName}` : " this organization";
            setFollowError(`Couldn't track${nameMsg}. Try again.`);
        }
    }, [isSignedIn, follow, onRequireSignIn, onFollowSuccess, orgName]);

    const handleUnfollowPress = useCallback(async () => {
        setFollowError(null);
        try {
            await unfollow();
            onUnfollowSuccess?.();
        } catch {
            const nameMsg = orgName ? ` ${orgName}` : "";
            setFollowError(`Couldn't stop tracking${nameMsg}. Try again.`);
        }
    }, [unfollow, onUnfollowSuccess, orgName]);

    const handlePreferencesPress = useCallback(() => {
        setIsFirstFollow(false);
        setPrefSheetOpenNonce((n) => n + 1);
        setShowPrefSheet(true);
    }, []);

    return {
        followId,
        isFollowing,
        showPrefSheet,
        setShowPrefSheet,
        prefSheetOpenNonce,
        isFirstFollow,
        followError,
        currentInitialPrefs,
        handlePrefsSave,
        handleFollowPress,
        handleUnfollowPress,
        handlePreferencesPress,
    };
}
