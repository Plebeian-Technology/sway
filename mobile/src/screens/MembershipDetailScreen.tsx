// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import React, { useCallback, useEffect, useRef, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { useNavigation, useRoute, type RouteProp } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import { useMembership } from "../hooks/useMembership";
import { useInviteAccept, InviteRefreshError } from "../hooks/useInviteAccept";
import { MembershipHeader } from "../components/MembershipHeader";
import { BroadsideTabStrip } from "../components/BroadsideTabStrip";
import { PositionsList } from "../components/PositionsList";
import { PendingChangesList } from "../components/PendingChangesList";
import { MembersList } from "../components/MembersList";
import { NewPositionModal } from "../components/NewPositionModal";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { ProfileStackParamList } from "../navigation/types";

type Nav = NativeStackNavigationProp<ProfileStackParamList, "MembershipDetail">;
type RouteType = RouteProp<ProfileStackParamList, "MembershipDetail">;

type TabKey = "positions" | "changes" | "members";

const ALL_TABS: { key: TabKey; label: string }[] = [
    { key: "positions", label: PARITY_COPY.memberships.tabPositions },
    { key: "changes", label: PARITY_COPY.memberships.tabPendingChanges },
    { key: "members", label: PARITY_COPY.memberships.tabMembers },
];

const LEGACY_ALIAS: Record<string, TabKey> = {
    positions: "positions",
    changes: "changes",
    approvals: "changes",
    members: "members",
};

export default function MembershipDetailScreen() {
    const navigation = useNavigation<Nav>();
    const route = useRoute<RouteType>();
    const { orgId, id, tab: tabParam } = route.params;

    const { data, loading, error: membershipError, refresh } = useMembership(orgId, id);

    const membership = data?.membership;
    const organization = membership?.organization;

    const acceptedRef = useRef(false);
    const [acceptError, setAcceptError] = useState<Error | null>(null);
    const { accept } = useInviteAccept({ refresh });

    const isPending = membership?.status === "pending";

    useEffect(() => {
        if (!isPending || acceptedRef.current || loading) return;
        acceptedRef.current = true;
        accept(orgId, id).catch((err: unknown) => {
            if (err instanceof InviteRefreshError) {
                return;
            }
            setAcceptError(err instanceof Error ? err : new Error(String(err)));
            acceptedRef.current = false;
        });
    }, [isPending, orgId, id, loading, accept]);

    const handleRetryAccept = useCallback(() => {
        setAcceptError(null);
        acceptedRef.current = true;
        accept(orgId, id).catch((err: unknown) => {
            if (err instanceof InviteRefreshError) {
                return;
            }
            setAcceptError(err instanceof Error ? err : new Error(String(err)));
            acceptedRef.current = false;
        });
    }, [accept, orgId, id]);

    const isAdmin = membership?.role === "admin";
    const isSway = (organization?.name ?? "").toLowerCase() === "sway";
    const membersOnlyAdminLayout = !__DEV__ && isSway && isAdmin;

    const visibleTabs: { key: TabKey; label: string }[] = membersOnlyAdminLayout
        ? ALL_TABS.filter((t) => t.key === "members")
        : isAdmin
          ? ALL_TABS
          : ALL_TABS.filter((t) => t.key !== "members");

    const defaultTab: TabKey = membersOnlyAdminLayout ? "members" : "positions";

    const fromParam = tabParam ? LEGACY_ALIAS[tabParam] : undefined;
    const resolvedInitial: TabKey = fromParam && visibleTabs.some((t) => t.key === fromParam) ? fromParam : defaultTab;

    const [activeTab, setActiveTab] = useState<TabKey>(resolvedInitial);
    const [showNewPositionModal, setShowNewPositionModal] = useState(false);

    const onTabChange = useCallback(
        (key: string) => {
            const tabKey = key as TabKey;
            setActiveTab(tabKey);
            navigation.setParams({ tab: tabKey });
        },
        [navigation],
    );

    if (loading && !membership) {
        return <View testID="membership-detail-screen" className="flex-1 bg-dominant-light dark:bg-dominant-dark" />;
    }

    const errorBanner = acceptError ? (
        <View
            testID="accept-error-banner"
            className="mx-4 mt-4 p-3 rounded-lg bg-destructive-light/10 dark:bg-destructive-dark/10 flex-row items-center justify-between"
        >
            <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark flex-1">
                Could not accept invite. Please try again.
            </Text>
            <Pressable
                testID="accept-retry-button"
                onPress={handleRetryAccept}
                accessibilityRole="button"
                className="ml-3 px-3 py-1 rounded bg-destructive-light dark:bg-destructive-dark"
            >
                <Text className="text-sm font-open-sans-semibold text-white">Retry</Text>
            </Pressable>
        </View>
    ) : null;

    const reloadErrorBanner =
        membershipError && membership ? (
            <View
                testID="membership-reload-error-banner"
                className="mx-4 mt-4 p-3 rounded-lg bg-destructive-light/10 dark:bg-destructive-dark/10 flex-row items-center justify-between"
            >
                <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark flex-1">
                    Could not update membership. Displaying cached data.
                </Text>
                <Pressable
                    testID="membership-reload-retry-button"
                    disabled={loading}
                    onPress={() => {
                        refresh().catch(() => {});
                    }}
                    accessibilityRole="button"
                    className="ml-3 px-3 py-1 rounded bg-destructive-light dark:bg-destructive-dark"
                >
                    <Text className="text-sm font-open-sans-semibold text-white">Retry</Text>
                </Pressable>
            </View>
        ) : null;

    if (membersOnlyAdminLayout) {
        return (
            <ScrollView
                testID="membership-detail-screen"
                className="flex-1 bg-dominant-light dark:bg-dominant-dark"
                contentInsetAdjustmentBehavior="automatic"
            >
                <MembershipHeader membership={membership} organization={organization}>
                    {errorBanner}
                    {reloadErrorBanner}
                    <MembersList
                        orgId={orgId}
                        members={membership?.members ?? []}
                        isAdmin={isAdmin}
                        currentUserId={membership?.user_id}
                    />
                </MembershipHeader>
            </ScrollView>
        );
    }

    return (
        <ScrollView
            testID="membership-detail-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentInsetAdjustmentBehavior="automatic"
        >
            <MembershipHeader membership={membership} organization={organization}>
                {errorBanner}
                {reloadErrorBanner}

                <BroadsideTabStrip
                    tabs={visibleTabs}
                    activeKey={activeTab}
                    onChange={onTabChange}
                    testID="membership-tab-strip"
                />

                {activeTab === "positions" && (
                    <>
                        <PositionsList
                            positions={membership?.positions ?? []}
                            isAdmin={isAdmin && !membersOnlyAdminLayout}
                            onProposeNew={() => setShowNewPositionModal(true)}
                        />
                        <NewPositionModal
                            visible={showNewPositionModal}
                            onClose={() => setShowNewPositionModal(false)}
                            orgId={orgId}
                            membershipId={id}
                            swayLocaleId={organization?.sway_locale_id}
                            onSuccess={refresh}
                        />
                    </>
                )}
                {activeTab === "changes" && (
                    <PendingChangesList
                        orgId={orgId}
                        membershipId={id}
                        isAdmin={isAdmin}
                        changes={membership?.pending_changes ?? []}
                        onRefresh={refresh}
                    />
                )}
                {activeTab === "members" && (
                    <MembersList
                        orgId={orgId}
                        members={membership?.members ?? []}
                        isAdmin={isAdmin}
                        currentUserId={membership?.user_id}
                    />
                )}
            </MembershipHeader>
        </ScrollView>
    );
}
