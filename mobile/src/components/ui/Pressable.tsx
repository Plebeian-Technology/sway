// @lat: [[mobile-shared-primitives-design#ui/Pressable]]
import React, { useCallback } from "react";
import { Pressable as RNPressable, type StyleProp, type ViewStyle } from "react-native";
import * as Haptics from "expo-haptics";
import { useTheme } from "../../theme/ThemeProvider";
import { shadowBold, pressFeedback } from "../../theme/effects";

export type PressableVariant = "default" | "destructive" | "outline" | "ghost";

export interface PressableProps {
    children: React.ReactNode;
    onPress: () => void;
    variant?: PressableVariant;
    disabled?: boolean;
    testID?: string;
    accessibilityLabel?: string;
    accessibilityHint?: string;
    accessibilityRole?: "button" | "checkbox" | "link" | "radio" | "switch";
    accessibilityState?: {
        checked?: boolean;
        expanded?: boolean;
        disabled?: boolean;
        selected?: boolean;
        busy?: boolean;
    };
    className?: string;
    style?: StyleProp<ViewStyle>;
}

// @lat: [[mobile-chrome-and-scroll-layout#Buttons are filled with the brand colour]]
const VARIANT_CLASSES: Record<PressableVariant, string> = {
    default: "bg-accent-light dark:bg-accent-dark border border-accent-light dark:border-accent-dark",
    destructive:
        "bg-destructive-light dark:bg-destructive-dark border border-destructive-light dark:border-destructive-dark",
    outline: "bg-surface-3-light dark:bg-surface-3-dark border-2 border-accent-light dark:border-accent-dark",
    ghost: "bg-transparent",
};

const BASE_CLASSES = "rounded-xl px-4 py-2 items-center justify-center";

export function Pressable({
    children,
    onPress,
    variant = "default",
    disabled = false,
    testID,
    accessibilityLabel,
    accessibilityHint,
    accessibilityRole = "button",
    accessibilityState,
    className,
    style,
}: PressableProps) {
    const { colorScheme } = useTheme();
    const merged = `${BASE_CLASSES} ${VARIANT_CLASSES[variant]}${className ? ` ${className}` : ""}`;
    const handlePress = useCallback(() => {
        // @lat: [[mobile-shared-primitives-design#ui/Pressable]]
        void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => undefined);
        onPress();
    }, [onPress]);
    return (
        <RNPressable
            testID={testID}
            accessibilityRole={accessibilityRole}
            accessibilityLabel={accessibilityLabel}
            accessibilityHint={accessibilityHint}
            accessibilityState={{ disabled, ...accessibilityState }}
            disabled={disabled}
            onPress={handlePress}
            className={merged}
            style={({ pressed }) => [
                { minHeight: 44, opacity: disabled ? 0.5 : 1 },
                variant !== "ghost" ? shadowBold(colorScheme) : null,
                pressFeedback(pressed, disabled),
                style,
            ]}
        >
            {children}
        </RNPressable>
    );
}
