// @lat: [[mobile-chrome-and-scroll-layout#The drawer panel opens with a brand block]]
import React from "react";
import { Image, Text, View } from "react-native";

import { useTheme } from "../theme/ThemeProvider";
import { chromeColors } from "../theme/chrome";

export default function DrawerBrandBlock(): React.ReactElement {
    const { colorScheme } = useTheme();
    const chrome = chromeColors(colorScheme);
    return (
        <View
            testID="drawer-brand-block"
            className="flex-row items-center gap-3 rounded-2xl px-4 py-3 mb-3"
            style={{
                backgroundColor: chrome.band,
                borderBottomWidth: chrome.bandEdgeWidth,
                borderBottomColor: chrome.bandEdge,
            }}
        >
            <Image
                // oxlint-disable-next-line @typescript-eslint/no-require-imports
                source={require("../../assets/sway-logo.png")}
                accessibilityLabel="Sway"
                resizeMode="cover"
                style={{ width: 44, height: 44, borderRadius: 10 }}
            />
            <View className="flex-1">
                <Text
                    className="text-2xl font-open-sans-semibold"
                    style={{ color: chrome.bandForeground }}
                    accessibilityRole="header"
                >
                    Sway
                </Text>
                <Text className="text-xs font-open-sans" style={{ color: chrome.bandForegroundMuted }}>
                    Remember in November
                </Text>
            </View>
        </View>
    );
}
