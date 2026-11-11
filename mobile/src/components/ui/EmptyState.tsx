// @lat: [[mobile-shared-primitives-design#ui/EmptyState]]
import React from "react";
import { Text, View } from "react-native";
import { Inbox } from "lucide-react-native";
import { Pressable } from "./Pressable";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";

export interface EmptyStateProps {
    title: string;
    body?: string;
    ctaLabel?: string;
    onCtaPress?: () => void;
    icon?: React.ReactNode;
    testID?: string;
    accessibilityLabel?: string;
    compact?: boolean;
}

export function EmptyState({
    title,
    body,
    ctaLabel,
    onCtaPress,
    icon,
    testID,
    accessibilityLabel,
    compact = false,
}: EmptyStateProps) {
    const { colorScheme } = useTheme();
    // @lat: [[mobile-shared-primitives-design#ui/EmptyState]]
    const resolvedIcon = icon ?? (
        <Inbox
            size={compact ? 24 : 40}
            strokeWidth={1.5}
            color={swayTokens[colorScheme].mutedIcon}
            accessibilityRole="none"
        />
    );
    return (
        <View
            testID={testID}
            accessibilityLabel={accessibilityLabel ?? title}
            className={`items-center ${compact ? "py-4" : "py-12"} gap-2`}
        >
            <View className="mb-2">{resolvedIcon}</View>
            <Text className="text-center text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {title}
            </Text>
            {body ? (
                <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark text-center">
                    {body}
                </Text>
            ) : null}
            {onCtaPress && ctaLabel ? (
                <View className="mt-6">
                    <Pressable
                        onPress={onCtaPress}
                        accessibilityLabel={ctaLabel}
                        testID={testID ? `${testID}-cta` : undefined}
                    >
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            {ctaLabel}
                        </Text>
                    </Pressable>
                </View>
            ) : null}
        </View>
    );
}
