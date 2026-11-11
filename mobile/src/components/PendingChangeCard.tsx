// @lat: [[mobile-org-membership-components-design#PendingChangeCard]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Card, CardContent, CardFooter, CardHeader } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { StampedBadge } from "./StampedBadge";
import { DestructiveSheet } from "./DestructiveSheet";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { PendingChangeRecord } from "../hooks/usePendingChanges";

export interface PendingChangeCardProps {
    change: PendingChangeRecord;
    isAdmin: boolean;
    onApprove: () => void;
    onReject: () => void;
    busy?: boolean;
    testID?: string;
}

export function PendingChangeCard({
    change,
    isAdmin,
    onApprove,
    onReject,
    busy = false,
    testID,
}: PendingChangeCardProps) {
    const [showRejectSheet, setShowRejectSheet] = useState(false);
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const supportColor = (support: string): string => (support === "FOR" ? t.voteFor : t.voteAgainst);

    const alreadyApproved = Boolean(change.approved_by_id);

    return (
        <>
            <Card testID={testID ?? `pending-change-card-${change.id}`} className="mb-3">
                <CardHeader>
                    <View className="flex-row items-center gap-3 flex-wrap">
                        <View className="flex-row items-center gap-2">
                            <Text
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                                style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                            >
                                Previous
                            </Text>
                            <StampedBadge
                                label={change.previous_support}
                                color={supportColor(change.previous_support)}
                            />
                        </View>
                        <View className="flex-row items-center gap-2">
                            <Text
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                                style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                            >
                                Proposed
                            </Text>
                            <StampedBadge label={change.new_support} color={supportColor(change.new_support)} />
                        </View>
                    </View>
                    <Text
                        className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                        style={{ fontVariant: ["tabular-nums"] }}
                    >
                        {change.created_at}
                    </Text>
                </CardHeader>

                <CardContent>
                    <View className="bg-surface-2-light dark:bg-surface-2-dark rounded-md p-3 mb-2">
                        <Text
                            className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mb-1"
                            style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                        >
                            Before
                        </Text>
                        <Text className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark">
                            {change.previous_summary}
                        </Text>
                    </View>
                    <View className="bg-surface-3-light dark:bg-surface-3-dark rounded-md p-3">
                        <Text
                            className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mb-1"
                            style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                        >
                            Proposed
                        </Text>
                        <Text className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark">
                            {change.new_summary}
                        </Text>
                    </View>
                </CardContent>

                {isAdmin && !alreadyApproved ? (
                    <CardFooter>
                        <Pressable
                            variant="default"
                            onPress={onApprove}
                            disabled={busy}
                            accessibilityLabel={PARITY_COPY.pendingChanges.approveLabel}
                        >
                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                {PARITY_COPY.pendingChanges.approveLabel}
                            </Text>
                        </Pressable>
                        <Pressable
                            variant="destructive"
                            onPress={() => setShowRejectSheet(true)}
                            disabled={busy}
                            accessibilityLabel={PARITY_COPY.pendingChanges.rejectLabel}
                        >
                            <Text className="text-sm font-open-sans-semibold text-white">
                                {PARITY_COPY.pendingChanges.rejectLabel}
                            </Text>
                        </Pressable>
                    </CardFooter>
                ) : alreadyApproved ? (
                    <CardFooter>
                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            Approved
                        </Text>
                    </CardFooter>
                ) : null}
            </Card>

            <DestructiveSheet
                visible={showRejectSheet}
                title={PARITY_COPY.pendingChanges.rejectConfirmTitle}
                body={PARITY_COPY.pendingChanges.rejectConfirmBody}
                actionLabel={PARITY_COPY.pendingChanges.rejectConfirmAction}
                onConfirm={() => {
                    setShowRejectSheet(false);
                    onReject();
                }}
                onDismiss={() => setShowRejectSheet(false)}
                busy={busy}
                testID="sheet-reject-change"
            />
        </>
    );
}

export default PendingChangeCard;
