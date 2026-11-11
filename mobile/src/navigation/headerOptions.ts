// @lat: [[mobile-tab-navigation-architecture#headerOptions.ts, the shared header settings]]
import React from "react";
import { Image } from "react-native";
import type { NativeStackNavigationOptions } from "@react-navigation/native-stack";
import { swayTokens } from "../theme/tokens";
import { chromeColors } from "../theme/chrome";

const HEADER_TITLE = (): React.ReactElement =>
    React.createElement(Image, {
        // oxlint-disable-next-line @typescript-eslint/no-require-imports
        source: require("../../assets/sway-logo.png"),
        accessibilityLabel: "Sway",
        style: { width: 32, height: 32, borderRadius: 8 },
        resizeMode: "cover",
    });

export function navigatorScreenOptions(colorScheme: "light" | "dark"): NativeStackNavigationOptions {
    const palette = colorScheme === "dark" ? swayTokens.dark : swayTokens.light;
    return {
        headerShown: false,
        contentStyle: { backgroundColor: palette.background },
    };
}

// @lat: [[mobile-chrome-and-scroll-layout#The brand band runs up under the status bar]]
export function pushedScreenOptions(colorScheme: "light" | "dark", backTitle: string): NativeStackNavigationOptions {
    const chrome = chromeColors(colorScheme);
    return {
        headerShown: true,
        headerTitle: HEADER_TITLE,
        headerTitleAlign: "center",
        headerBackTitle: backTitle,
        headerStyle: { backgroundColor: chrome.band },
        headerShadowVisible: false,
        headerTintColor: chrome.bandForeground,
    };
}
