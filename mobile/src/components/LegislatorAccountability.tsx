// @lat: [[mobile-legislator-components-design#LegislatorAccountability]]
import React from "react";
import { View, Text } from "react-native";

import { StampedBadge } from "./StampedBadge";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

export interface AccountabilityRow {
    bill_id: number;
    bill_title: string;
    user_support: "for" | "against" | null;
    legislator_support: "for" | "against" | "abstain" | null;
}

export interface LegislatorAccountabilityProps {
    rows: AccountabilityRow[];
    testID?: string;
}

export function LegislatorAccountability({ rows, testID }: LegislatorAccountabilityProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    if (!rows || rows.length === 0) {
        return (
            <View testID={testID ?? "accountability-empty"} className="mt-4">
                <Text
                    accessibilityRole="text"
                    className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                >
                    No vote comparisons yet — vote on bills your representative has voted on to see alignment.
                </Text>
            </View>
        );
    }

    return (
        <View testID={testID ?? "legislator-accountability"} className="mt-4">
            <Text
                accessibilityRole="header"
                className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-3"
            >
                How they compare to your votes
            </Text>
            {rows.map((row) => {
                const both = row.user_support && row.legislator_support;
                // @lat: [[mobile-legislator-components-design#LegislatorAccountability]]
                const aligned = both && row.user_support === row.legislator_support;
                const label = aligned ? "Aligned" : "Divergent";
                const color = aligned ? t.voteFor : t.voteAgainst;
                return (
                    <View
                        key={row.bill_id}
                        testID={`accountability-row-${row.bill_id}`}
                        className="flex-row justify-between items-center py-2 border-b border-border-light dark:border-border-dark"
                        accessibilityRole="summary"
                        accessibilityLabel={`${row.bill_title}: ${label}`}
                    >
                        <Text
                            className="flex-1 text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                            numberOfLines={2}
                        >
                            {row.bill_title}
                        </Text>
                        <View className="ml-3">
                            <StampedBadge label={label} color={color} testID={`accountability-badge-${row.bill_id}`} />
                        </View>
                    </View>
                );
            })}
        </View>
    );
}

export default LegislatorAccountability;
