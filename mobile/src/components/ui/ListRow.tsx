// @lat: [[mobile-shared-primitives-design#ui/ListRow]]
import React from "react";
import { Pressable as RNPressable, Text, View } from "react-native";
import { pressFeedback } from "../../theme/effects";

export interface ListRowProps {
    label: string;
    description?: string;
    onPress?: () => void;
    leftSlot?: React.ReactNode;
    rightSlot?: React.ReactNode;
    testID?: string;
    accessibilityLabel?: string;
    accessibilityHint?: string;
}

const BASE_CLASSES =
    "bg-card-light dark:bg-card-dark " +
    "border-b border-border-soft-light dark:border-border-soft-dark " +
    "flex-row items-center justify-between px-4 py-3";

export function ListRow({
    label,
    description,
    onPress,
    leftSlot,
    rightSlot,
    testID,
    accessibilityLabel,
    accessibilityHint,
}: ListRowProps) {
    const inner = (
        <>
            <View className="flex-row items-center gap-3 flex-1">
                {leftSlot ? <View>{leftSlot}</View> : null}
                <View className="flex-1">
                    <Text className="text-base font-open-sans text-foreground-light dark:text-foreground-dark">
                        {label}
                    </Text>
                    {description ? (
                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mt-1">
                            {description}
                        </Text>
                    ) : null}
                </View>
            </View>
            <View className="flex-row items-center gap-2">
                {rightSlot ? <View>{rightSlot}</View> : null}
                {onPress ? (
                    <Text
                        testID={testID ? `${testID}-chevron` : "list-row-chevron"}
                        className="text-xl font-open-sans-semibold text-accent-light dark:text-accent-dark"
                    >
                        {"›"}
                    </Text>
                ) : null}
            </View>
        </>
    );
    if (onPress) {
        return (
            <RNPressable
                testID={testID}
                accessibilityRole="button"
                accessibilityLabel={accessibilityLabel ?? label}
                accessibilityHint={accessibilityHint}
                onPress={onPress}
                className={BASE_CLASSES}
                style={({ pressed }) => [{ minHeight: 44 }, pressFeedback(pressed)]}
            >
                {inner}
            </RNPressable>
        );
    }
    return (
        <View
            testID={testID}
            accessibilityRole="none"
            accessibilityLabel={accessibilityLabel ?? label}
            className={BASE_CLASSES}
            style={{ minHeight: 44 }}
        >
            {inner}
        </View>
    );
}
