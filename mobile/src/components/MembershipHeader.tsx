import React from "react";
import { Text, View } from "react-native";

import { StampedBadge } from "./StampedBadge";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

export interface MembershipHeaderProps {
    membership?: {
        id?: number;
        role?: "admin" | "standard";
        organization?: {
            id?: number;
            name?: string;
            member_count?: number;
        } & Record<string, unknown>;
    } & Record<string, unknown>;
    organization?: {
        id?: number;
        name?: string;
        member_count?: number;
    } & Record<string, unknown>;
    children?: React.ReactNode;
    testID?: string;
}

export function MembershipHeader({ membership, organization, children, testID }: MembershipHeaderProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    // @lat: [[mobile-org-membership-components-design#MembershipHeader]]
    const org = organization ?? membership?.organization;
    const orgName = org?.name ?? "Organization";
    const memberCount = org?.member_count;
    const role = membership?.role ?? "standard";
    const isAdmin = role === "admin";

    return (
        <View testID={testID ?? "membership-header"} className="flex-1">
            <View className="px-4 py-6 border-b border-border-light dark:border-border-dark">
                <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {orgName}
                </Text>
                <View className="flex-row items-center gap-2 mt-2">
                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        Your role:
                    </Text>
                    <StampedBadge
                        label={isAdmin ? "Admin" : "Member"}
                        color={isAdmin ? t.primary : t.mutedForeground}
                    />
                </View>
                {memberCount !== undefined ? (
                    <Text
                        className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mt-1"
                        style={{ fontVariant: ["tabular-nums"] }}
                    >
                        {memberCount} member{memberCount !== 1 ? "s" : ""}
                    </Text>
                ) : null}
            </View>
            {children}
        </View>
    );
}

export default MembershipHeader;
