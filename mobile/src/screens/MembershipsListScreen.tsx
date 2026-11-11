// @lat: [[mobile-membership-screens#MembershipsListScreen]]
import React, { useCallback, useState } from "react";
import { RefreshControl, ScrollView, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import { useMemberships } from "../hooks/useMemberships";
import { useInviteAccept } from "../hooks/useInviteAccept";
import { useReachability } from "../hooks/useReachability";
import { MembershipCard } from "../components/MembershipCard";
import { DestructiveSheet } from "../components/DestructiveSheet";
import { EmptyState } from "../components/ui/EmptyState";
import { FadeInItem } from "../components/ui/FadeInItem";
import { OfflineBanner } from "../components/OfflineBanner";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { ProfileStackParamList } from "../navigation/types";

type Nav = NativeStackNavigationProp<ProfileStackParamList>;

interface PendingDecline {
    orgId: number;
    id: number;
}

export default function MembershipsListScreen() {
    const navigation = useNavigation<Nav>();
    const { isOnline, isResolved } = useReachability();
    const { active, pending, loading, refresh } = useMemberships();
    const { accept, decline } = useInviteAccept({ refresh });

    const [pendingDecline, setPendingDecline] = useState<PendingDecline | null>(null);
    const [declining, setDeclining] = useState(false);

    const onRefresh = useCallback(async () => {
        await refresh();
    }, [refresh]);

    const handleAccept = useCallback(
        async (orgId: number, id: number) => {
            await accept(orgId, id).catch(() => {});
        },
        [accept],
    );

    const handleDeclineRequest = useCallback((orgId: number, id: number) => {
        setPendingDecline({ orgId, id });
    }, []);

    const handleDeclineConfirm = useCallback(async () => {
        if (!pendingDecline) return;
        setDeclining(true);
        try {
            await decline(pendingDecline.orgId, pendingDecline.id);
        } catch {
            // @lat: [[mobile-membership-screens#MembershipsListScreen]]
        } finally {
            setDeclining(false);
            setPendingDecline(null);
        }
    }, [decline, pendingDecline]);

    const handleDeclineDismiss = useCallback(() => {
        setPendingDecline(null);
    }, []);

    return (
        <>
            <ScrollView
                testID="memberships-list-screen"
                className="flex-1 bg-dominant-light dark:bg-dominant-dark"
                contentInsetAdjustmentBehavior="automatic"
                refreshControl={<RefreshControl refreshing={loading} onRefresh={onRefresh} />}
            >
                {!isOnline && isResolved ? <OfflineBanner /> : null}

                <View testID="memberships-active-section" className="px-4 pt-6">
                    <Text
                        className="text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mb-3"
                        style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                    >
                        {PARITY_COPY.memberships.activeSectionLabel}
                    </Text>
                    {active.length === 0 ? (
                        <EmptyState title={PARITY_COPY.memberships.activeEmpty} />
                    ) : (
                        active.map((membership, index) => (
                            <FadeInItem key={membership.id} index={index}>
                                <MembershipCard
                                    membership={membership}
                                    variant="active"
                                    onPress={() =>
                                        navigation.navigate("MembershipDetail", {
                                            orgId: (membership.organization?.id as number) ?? 0,
                                            id: membership.id,
                                        })
                                    }
                                />
                            </FadeInItem>
                        ))
                    )}
                </View>

                <View testID="memberships-pending-section" className="px-4 pt-6 pb-8">
                    <Text
                        className="text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mb-3"
                        style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                    >
                        {PARITY_COPY.memberships.pendingSectionLabel}
                    </Text>
                    {pending.length === 0 ? (
                        <EmptyState title={PARITY_COPY.memberships.pendingEmpty} />
                    ) : (
                        pending.map((membership, index) => (
                            <FadeInItem key={membership.id} index={index}>
                                <MembershipCard
                                    membership={membership}
                                    variant="pending"
                                    onAccept={() =>
                                        handleAccept((membership.organization?.id as number) ?? 0, membership.id)
                                    }
                                    onDecline={() =>
                                        handleDeclineRequest(
                                            (membership.organization?.id as number) ?? 0,
                                            membership.id,
                                        )
                                    }
                                />
                            </FadeInItem>
                        ))
                    )}
                </View>
            </ScrollView>

            <DestructiveSheet
                visible={pendingDecline !== null}
                title={PARITY_COPY.memberships.declineConfirmTitle}
                body={PARITY_COPY.memberships.declineConfirmBody}
                actionLabel={PARITY_COPY.memberships.declineConfirmAction}
                onConfirm={handleDeclineConfirm}
                onDismiss={handleDeclineDismiss}
                busy={declining}
                testID="decline-invite-sheet"
            />
        </>
    );
}
