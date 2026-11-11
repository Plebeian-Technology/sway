// @lat: [[mobile-shared-primitives-design#ui/SegmentedControl]]
import React from "react";
import { Pressable, Text, View } from "react-native";
import * as Haptics from "expo-haptics";

import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { readableForeground } from "../StampedBadge";

export interface SegmentedControlProps {
    segments: string[];
    selectedIndex: number;
    onChange: (index: number) => void;
    testID?: string;
    accessibilityLabel?: string;
}

export function SegmentedControl({
    segments,
    selectedIndex,
    onChange,
    testID,
    accessibilityLabel,
}: SegmentedControlProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const activeForeground = readableForeground(t.primary);
    const rootTestID = testID ?? "segmented-control";

    return (
        <View
            testID={rootTestID}
            accessibilityRole="tablist"
            accessibilityLabel={accessibilityLabel}
            className="flex-row bg-surface-3-light dark:bg-surface-3-dark border border-accent-light dark:border-accent-dark rounded-xl p-1 gap-1"
        >
            {segments.map((label, index) => {
                const selected = index === selectedIndex;
                return (
                    <Pressable
                        key={`${index}-${label}`}
                        testID={`${rootTestID}-segment-${index}`}
                        accessibilityRole="tab"
                        accessibilityState={{ selected }}
                        accessibilityLabel={label}
                        onPress={() => {
                            // @lat: [[mobile-shared-primitives-design#ui/Pressable#Haptic feedback is fire-and-forget]]
                            void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => undefined);
                            onChange(index);
                        }}
                        className={`flex-1 items-center justify-center rounded-lg px-1 ${
                            selected ? "bg-accent-light dark:bg-accent-dark" : "bg-transparent"
                        }`}
                        style={{ minHeight: 44 }}
                    >
                        <Text
                            className={`text-sm font-open-sans-semibold${
                                selected ? "" : " text-foreground-light dark:text-foreground-dark"
                            }`}
                            style={selected ? { color: activeForeground } : undefined}
                            numberOfLines={1}
                        >
                            {label}
                        </Text>
                    </Pressable>
                );
            })}
        </View>
    );
}

export default SegmentedControl;
