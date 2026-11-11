// @lat: [[mobile-shared-primitives-design#ui/Card]]
import React from "react";
import { Pressable as RNPressable, Text, View, type StyleProp, type ViewStyle } from "react-native";
import { useTheme } from "../../theme/ThemeProvider";
import { shadowBold, pressFeedback } from "../../theme/effects";

export interface CardProps {
    children: React.ReactNode;
    onPress?: () => void;
    testID?: string;
    accessibilityLabel?: string;
    className?: string;
    style?: StyleProp<ViewStyle>;
    // @lat: [[mobile-chrome-and-scroll-layout#Cards carry a coloured edge]]
    accentColor?: string;
}

const BASE_CLASSES =
    "bg-card-light dark:bg-card-dark " +
    "border border-border-soft-light dark:border-border-soft-dark " +
    "rounded-card px-4 py-4 gap-3";

const ACCENT_EDGE_WIDTH = 5;

export function Card({ children, onPress, testID, accessibilityLabel, className, style, accentColor }: CardProps) {
    const { colorScheme } = useTheme();
    const merged = `${BASE_CLASSES}${className ? ` ${className}` : ""}`;
    const accentStyle: ViewStyle | null = accentColor
        ? { borderLeftWidth: ACCENT_EDGE_WIDTH, borderLeftColor: accentColor }
        : null;
    if (onPress) {
        return (
            <RNPressable
                testID={testID}
                accessibilityRole="button"
                accessibilityLabel={accessibilityLabel}
                onPress={onPress}
                className={merged}
                style={({ pressed }) => [shadowBold(colorScheme), accentStyle, pressFeedback(pressed), style]}
            >
                {children}
            </RNPressable>
        );
    }
    return (
        <View
            testID={testID}
            accessible={!!accessibilityLabel}
            accessibilityLabel={accessibilityLabel}
            className={merged}
            style={[shadowBold(colorScheme), accentStyle, style]}
        >
            {children}
        </View>
    );
}

export function CardHeader({ children, className }: { children: React.ReactNode; className?: string }) {
    return <View className={`gap-2${className ? ` ${className}` : ""}`}>{children}</View>;
}

export function CardTitle({ children, className }: { children: React.ReactNode; className?: string }) {
    return (
        <Text
            accessibilityRole="header"
            className={`text-xl font-open-sans-semibold text-card-foreground-light dark:text-card-foreground-dark${className ? ` ${className}` : ""}`}
        >
            {children}
        </Text>
    );
}

export function CardContent({ children, className }: { children: React.ReactNode; className?: string }) {
    return <View className={`gap-2${className ? ` ${className}` : ""}`}>{children}</View>;
}

export function CardFooter({ children, className }: { children: React.ReactNode; className?: string }) {
    return (
        <View className={`flex-row items-center justify-between${className ? ` ${className}` : ""}`}>{children}</View>
    );
}
