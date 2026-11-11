import React from "react";
import { Text, View } from "react-native";

import { PositionCard } from "./PositionCard";
import { Pressable } from "./ui/Pressable";
import { EmptyState } from "./ui/EmptyState";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { OrgPositionDisplay } from "./PositionCard";

export interface PositionsListProps {
    positions: OrgPositionDisplay[];
    loading?: boolean;
    isAdmin?: boolean;
    onProposeNew?: () => void;
    testID?: string;
}

export function PositionsList({
    positions,
    loading = false,
    isAdmin = false,
    onProposeNew,
    testID,
}: PositionsListProps) {
    const header =
        isAdmin && onProposeNew ? (
            <View className="px-4 pt-4 pb-2">
                <Pressable
                    variant="default"
                    onPress={onProposeNew}
                    accessibilityLabel={PARITY_COPY.memberships.tabPositions}
                >
                    <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                        {PARITY_COPY.positions.newModalTitle}
                    </Text>
                </Pressable>
            </View>
        ) : null;

    if (!loading && positions.length === 0) {
        return (
            <View testID={testID ?? "positions-list"} className="flex-1">
                {header}
                <EmptyState title={PARITY_COPY.positions.empty} />
            </View>
        );
    }

    return (
        <View testID={testID ?? "positions-list"} style={{ padding: 16 }}>
            {header}
            {positions.map((item) => (
                <PositionCard key={item.id} position={item} />
            ))}
        </View>
    );
}

export default PositionsList;
