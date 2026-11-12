// @lat: [[theme-token-contract#Mobile's twin: swayTokens#Where effects.ts's shadow values come from]]
import type { ViewStyle } from "react-native";
import type { SwayColorScheme } from "./tokens";

export const shadowBold = (colorScheme: SwayColorScheme) =>
    ({
        // @lat: [[theme-token-contract#Mobile's twin: swayTokens#Where effects.ts's shadow values come from]]
        shadowColor: "#000000",
        shadowOffset: { width: 0, height: colorScheme === "dark" ? 2 : 3 },
        shadowOpacity: colorScheme === "dark" ? 0.5 : 0.1,
        shadowRadius: colorScheme === "dark" ? 4 : 6,
        elevation: colorScheme === "dark" ? 4 : 3,
    }) as const;

export type ShadowBoldStyle = ReturnType<typeof shadowBold>;

// @lat: [[theme-token-contract#Mobile's twin: swayTokens#Why pressFeedback exists]]
export const pressFeedback = (pressed: boolean, disabled = false): ViewStyle | null =>
    pressed && !disabled ? { opacity: 0.85, transform: [{ scale: 0.97 }] } : null;
