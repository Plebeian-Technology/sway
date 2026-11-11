// @lat: [[mobile-org-membership-components-design#MembershipCard]]
import React from "react";
import { Pressable, Text, View } from "react-native";

import { Card, CardContent, CardHeader } from "./ui/Card";
import { StampedBadge } from "./StampedBadge";
import type { MembershipRecord } from "../hooks/useMemberships";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface MembershipCardProps {
    membership: MembershipRecord;
    variant: "active" | "pending";
    onPress?: () => void;
    onAccept?: () => void;
    onDecline?: () => void;
    testID?: string;
}

export function MembershipCard({ membership, variant, onPress, onAccept, onDecline, testID }: MembershipCardProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const cardTestID = testID ?? `membership-card-${membership.id}`;
    const orgName = membership.organization?.name ?? "Unknown organization";
    const memberCount = membership.organization?.member_count;
    const isAdmin = membership.role === "admin";

    const content = (
        <Card testID={cardTestID} className="mb-2">
            <CardHeader>
                <Text className="text-xl font-open-sans-semibold text-card-foreground-light dark:text-card-foreground-dark">
                    {orgName}
                </Text>
                {memberCount !== undefined ? (
                    <Text
                        className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                        style={{ fontVariant: ["tabular-nums"] }}
                    >
                        {memberCount} member{memberCount !== 1 ? "s" : ""}
                    </Text>
                ) : null}
            </CardHeader>
            <CardContent>
                <View className="flex-row items-center justify-between">
                    <StampedBadge
                        label={isAdmin ? "Admin" : "Member"}
                        color={isAdmin ? t.primary : t.mutedForeground}
                    />
                    {variant === "pending" ? (
                        <View className="flex-row gap-2">
                            <Pressable
                                onPress={onAccept ?? (() => {})}
                                accessibilityRole="button"
                                accessibilityLabel={PARITY_COPY.memberships.acceptLabel}
                                className="px-3 py-2 bg-accent-light dark:bg-accent-dark rounded-lg"
                            >
                                <Text className="text-sm font-open-sans-semibold text-accent-foreground-light dark:text-accent-foreground-dark">
                                    {PARITY_COPY.memberships.acceptLabel}
                                </Text>
                            </Pressable>
                            <Pressable
                                onPress={onDecline ?? (() => {})}
                                accessibilityRole="button"
                                accessibilityLabel={PARITY_COPY.memberships.declineLabel}
                                className="px-3 py-2 border border-border-light dark:border-border-dark rounded-lg"
                            >
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    {PARITY_COPY.memberships.declineLabel}
                                </Text>
                            </Pressable>
                        </View>
                    ) : null}
                </View>
            </CardContent>
        </Card>
    );

    if (variant === "active" && onPress) {
        return (
            <Pressable
                testID={cardTestID}
                onPress={onPress}
                accessibilityRole="button"
                accessibilityLabel={`Open ${orgName} membership`}
            >
                {/* @lat: [[mobile-org-membership-components-design#MembershipCard]] */}
                <Card className="mb-2">
                    <CardHeader>
                        <Text className="text-xl font-open-sans-semibold text-card-foreground-light dark:text-card-foreground-dark">
                            {orgName}
                        </Text>
                        {memberCount !== undefined ? (
                            <Text
                                className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                                style={{ fontVariant: ["tabular-nums"] }}
                            >
                                {memberCount} member{memberCount !== 1 ? "s" : ""}
                            </Text>
                        ) : null}
                    </CardHeader>
                    <CardContent>
                        <StampedBadge
                            label={isAdmin ? "Admin" : "Member"}
                            color={isAdmin ? t.primary : t.mutedForeground}
                        />
                    </CardContent>
                </Card>
            </Pressable>
        );
    }

    return content;
}

export default MembershipCard;
