// @lat: [[mobile-org-detail-screen#OrgDetailScreen]]
import React, { useCallback, useEffect, useState } from "react";
import { RefreshControl, ScrollView, Text, View } from "react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { apiClient } from "../api/client";
import { PositionsList } from "../components/PositionsList";
import type { OrgPositionDisplay } from "../components/PositionCard";
import { Pressable } from "../components/ui/Pressable";
import { OrgPreferenceSheet } from "../components/OrgPreferenceSheet";
import type { OrgFollowPrefs } from "../hooks/useOrganizationFollow";
import { useOrgFollowSheet } from "../hooks/useOrgFollowSheet";
import type { OrganizationRecord, OrgFollowPref, OrgDefaultPrefs } from "../hooks/useOrganizations";

interface OrgPosition {
    id: number;
    bill_id: number;
    support: string;
    summary: string;
    active?: boolean;
    created_at?: string;
    source_kind?: OrgPositionDisplay["source_kind"];
}

interface OrgDetailPayload {
    organization: OrganizationRecord;
    organization_bill_positions: OrgPosition[];
    current_user_follow_id?: number;
    is_member_of_org_ids?: number[];
    // @lat: [[mobile-org-detail-screen#OrgDetailPayload's follow-preference fields]]
    user_follow_prefs?: Record<number, OrgFollowPref>;
    current_user_org_defaults?: OrgDefaultPrefs;
}

interface RouteLike {
    params: { id: number };
}

interface NavLike {
    navigate: (screen: string, params?: Record<string, unknown>) => void;
}

interface OrgDetailScreenProps {
    route: RouteLike;
    navigation?: NavLike;
}

// @lat: [[mobile-org-detail-screen#Why OrgDetailFollowSection is its own component]]
interface OrgDetailFollowSectionProps {
    orgId: number;
    orgName: string;
    initialFollowId: number | null;
    isMember: boolean;
    initialPrefs?: OrgFollowPrefs;
    defaultPrefs?: OrgFollowPrefs;
}

function OrgDetailFollowSection({
    orgId,
    orgName,
    initialFollowId,
    isMember,
    initialPrefs,
    defaultPrefs,
}: OrgDetailFollowSectionProps) {
    const {
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
    } = useOrgFollowSheet({
        orgId,
        initialFollowId,
        isMember,
        initialPrefs,
        defaultPrefs,
    });

    return (
        <>
            <View className="mt-3 gap-2">
                {isMember ? (
                    <>
                        <Text
                            testID="org-detail-member-label"
                            className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                        >
                            Member
                        </Text>
                        <Pressable
                            testID="org-detail-preferences-btn"
                            variant="outline"
                            onPress={handlePreferencesPress}
                            accessibilityLabel="Open notification preferences for this organization"
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                Preferences
                            </Text>
                        </Pressable>
                    </>
                ) : isFollowing ? (
                    <Pressable
                        testID="org-detail-following-btn"
                        variant="outline"
                        onPress={handleUnfollowPress}
                        accessibilityLabel={`Untrack ${orgName}`}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.orgs.tracking}
                        </Text>
                    </Pressable>
                ) : (
                    <Pressable
                        testID="org-detail-follow-btn"
                        variant="default"
                        onPress={handleFollowPress}
                        accessibilityLabel={`Track ${orgName}`}
                    >
                        <Text className="text-sm font-open-sans-semibold text-white">{PARITY_COPY.orgs.track}</Text>
                    </Pressable>
                )}
                {followError ? (
                    <Text
                        testID="org-detail-follow-error"
                        accessibilityRole="alert"
                        className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                    >
                        {followError}
                    </Text>
                ) : null}
            </View>

            {/* @lat: [[mobile-org-detail-screen#The notification-settings sheet]] */}
            <OrgPreferenceSheet
                key={`org-detail-pref-sheet-open-${prefSheetOpenNonce}`}
                visible={showPrefSheet}
                orgName={orgName}
                isFirstFollow={isFirstFollow}
                initialPrefs={currentInitialPrefs}
                onSave={handlePrefsSave}
                onClose={() => setShowPrefSheet(false)}
                testID="org-detail-pref-sheet"
            />
        </>
    );
}

export default function OrgDetailScreen({ route }: OrgDetailScreenProps) {
    const orgId = route.params.id;
    const [data, setData] = useState<OrgDetailPayload | null>(null);
    const [loading, setLoading] = useState<boolean>(true);

    const refresh = useCallback(async () => {
        setLoading(true);
        try {
            const payload = await apiClient.get<OrgDetailPayload>(`/public/organizations/${orgId}`);
            setData(payload);
        } catch {
        } finally {
            setLoading(false);
        }
    }, [orgId]);

    useEffect(() => {
        void refresh();
    }, [refresh]);

    if (!data && loading) {
        return (
            <View className="p-4" testID="org-detail-loading">
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Loading organization…
                </Text>
            </View>
        );
    }

    if (!data) {
        return (
            <View className="p-4" testID="org-detail-error">
                <Text
                    accessibilityRole="alert"
                    className="text-sm font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark"
                >
                    Could not load organization. Pull to refresh.
                </Text>
            </View>
        );
    }

    const org = data.organization;
    const positions = data.organization_bill_positions ?? [];

    const isSignedIn = data.current_user_follow_id !== undefined || data.is_member_of_org_ids !== undefined;
    const isMember = isSignedIn && (data.is_member_of_org_ids?.includes(orgId) ?? false);
    const initialFollowId = data.current_user_follow_id ?? null;

    return (
        <ScrollView
            contentContainerStyle={{ padding: 16 }}
            refreshControl={<RefreshControl refreshing={loading} onRefresh={() => void refresh()} />}
        >
            <View testID="org-detail-header" className="mb-4">
                <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-1">
                    {org.name}
                </Text>
                {org.sway_locale_slug ? (
                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        {org.sway_locale_slug}
                    </Text>
                ) : null}
                {/* @lat: [[organization-affiliation-labels#Organization affiliation labels#Organization pages say whether the organization takes part]] */}
                <Text
                    testID="org-detail-affiliation"
                    className="mt-2 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                >
                    {org.managed_on_sway
                        ? PARITY_COPY.orgs.managedOnSway(org.name)
                        : PARITY_COPY.orgs.notAffiliated(org.name)}
                </Text>

                {isSignedIn ? (
                    // @lat: [[mobile-org-detail-screen#Why the follow section is keyed on the server-assigned follow id]]
                    <OrgDetailFollowSection
                        key={`org-follow-section-${initialFollowId ?? "none"}`}
                        orgId={orgId}
                        orgName={org.name}
                        initialFollowId={initialFollowId}
                        isMember={isMember}
                        initialPrefs={data.user_follow_prefs?.[orgId]}
                        defaultPrefs={data.current_user_org_defaults}
                    />
                ) : null}
            </View>

            <View testID="org-detail-positions">
                <PositionsList positions={positions} isAdmin={false} organizationName={org.name} />
            </View>
        </ScrollView>
    );
}
