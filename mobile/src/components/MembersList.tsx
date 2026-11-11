import React, { useState } from "react";
import { FlatList, Text, View } from "react-native";

import { MemberInviteForm } from "./MemberInviteForm";
import { DestructiveSheet } from "./DestructiveSheet";
import { Pressable } from "./ui/Pressable";
import { StampedBadge } from "./StampedBadge";
import { EmptyState } from "./ui/EmptyState";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface OrgMemberRecord {
    id: number;
    user_id: number;
    full_name: string;
    email?: string;
    role: "admin" | "standard";
}

export interface MembersListProps {
    orgId: number;
    members: OrgMemberRecord[];
    isAdmin?: boolean;
    currentUserId?: number;
    onLeave?: () => void;
    testID?: string;
}

export function MembersList({ orgId, members, isAdmin = false, currentUserId, onLeave, testID }: MembersListProps) {
    const [showLeaveSheet, setShowLeaveSheet] = useState(false);
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const header = isAdmin ? (
        <View className="px-4 pt-4">
            <MemberInviteForm orgId={orgId} />
        </View>
    ) : null;

    if (members.length === 0 && !isAdmin) {
        return (
            <View testID={testID ?? "members-list"} className="flex-1">
                <EmptyState title={PARITY_COPY.members.empty} />
            </View>
        );
    }

    return (
        <>
            <FlatList
                testID={testID ?? "members-list"}
                data={members}
                keyExtractor={(item) => String(item.id)}
                ListHeaderComponent={header}
                ListEmptyComponent={
                    <View className="p-4">
                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark text-center">
                            {PARITY_COPY.members.empty}
                        </Text>
                    </View>
                }
                renderItem={({ item }) => {
                    const isCurrentUser = currentUserId !== undefined && item.user_id === currentUserId;
                    const roleColor = item.role === "admin" ? t.primary : t.mutedForeground;
                    const roleLabel = item.role === "admin" ? "ADMIN" : "MEMBER";

                    return (
                        <View
                            className="flex-row items-center justify-between px-4 py-3 border-b border-border-soft-light dark:border-border-soft-dark"
                            accessibilityRole="text"
                            accessibilityLabel={`${item.full_name}, ${item.role}`}
                        >
                            <View className="flex-1 gap-1">
                                <Text className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                    {item.full_name}
                                </Text>
                                {item.email ? (
                                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {item.email}
                                    </Text>
                                ) : null}
                            </View>
                            <View className="flex-row items-center gap-3">
                                <StampedBadge label={roleLabel} color={roleColor} />
                                {isCurrentUser && onLeave ? (
                                    <Pressable
                                        variant="destructive"
                                        onPress={() => setShowLeaveSheet(true)}
                                        accessibilityLabel={PARITY_COPY.members.leaveOrgLabel}
                                    >
                                        <Text className="text-xs font-open-sans-semibold text-white">
                                            {PARITY_COPY.members.leaveOrgLabel}
                                        </Text>
                                    </Pressable>
                                ) : null}
                            </View>
                        </View>
                    );
                }}
                contentContainerStyle={{ paddingBottom: 16 }}
            />

            {onLeave ? (
                <DestructiveSheet
                    visible={showLeaveSheet}
                    title={PARITY_COPY.members.leaveOrgConfirmTitle}
                    body={PARITY_COPY.members.leaveOrgConfirmBody}
                    actionLabel={PARITY_COPY.members.leaveOrgConfirmAction}
                    onConfirm={() => {
                        setShowLeaveSheet(false);
                        onLeave();
                    }}
                    onDismiss={() => setShowLeaveSheet(false)}
                    testID="sheet-leave-org"
                />
            ) : null}
        </>
    );
}

export default MembersList;
