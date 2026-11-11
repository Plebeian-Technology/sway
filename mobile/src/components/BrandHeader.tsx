// @lat: [[mobile-shared-primitives-design#BrandHeader]]
import React from "react";
import { Image, Text, View } from "react-native";
import { Menu } from "lucide-react-native";
import { Pressable } from "./ui/Pressable";
import { useTheme } from "../theme/ThemeProvider";
import { chromeColors } from "../theme/chrome";

// @lat: [[mobile-chrome-and-scroll-layout#The pinned header is one 56pt row]]
export const BRAND_HEADER_MIN_HEIGHT = 56;

interface Props {
    title: string;
    testID?: string;
    onMenuPress?: () => void;
    titleAction?: { onPress: () => void; accessibilityLabel: string };
}

export default function BrandHeader({
    title,
    testID = "brand-header",
    onMenuPress,
    titleAction,
}: Props): React.ReactElement {
    const { colorScheme } = useTheme();
    const chrome = chromeColors(colorScheme);
    const titleText = (
        <Text
            className="flex-1 text-xl font-open-sans-semibold"
            style={{ color: chrome.bandForeground }}
            numberOfLines={2}
            accessibilityRole="header"
        >
            {title}
        </Text>
    );
    return (
        <View
            className="flex-row items-center gap-2 px-2 py-1.5"
            testID={testID}
            style={{
                minHeight: BRAND_HEADER_MIN_HEIGHT,
                backgroundColor: chrome.band,
                borderBottomWidth: chrome.bandEdgeWidth,
                borderBottomColor: chrome.bandEdge,
            }}
        >
            {onMenuPress ? (
                <Pressable
                    variant="ghost"
                    onPress={onMenuPress}
                    testID="brand-header-menu"
                    accessibilityRole="button"
                    accessibilityLabel="Open menu"
                    className="w-11 h-11 !px-0 !py-0"
                >
                    <Menu size={26} color={chrome.bandForeground} strokeWidth={2.25} />
                </Pressable>
            ) : (
                <View className="w-1" />
            )}
            <Image
                // oxlint-disable-next-line @typescript-eslint/no-require-imports
                source={require("../../assets/sway-logo.png")}
                accessibilityLabel="Sway"
                resizeMode="cover"
                style={{ width: 32, height: 32, borderRadius: 8 }}
            />
            {titleAction ? (
                <Pressable
                    variant="ghost"
                    onPress={titleAction.onPress}
                    testID="brand-header-title-button"
                    accessibilityRole="button"
                    accessibilityLabel={titleAction.accessibilityLabel}
                    className="flex-1 flex-row !px-0 !py-0"
                >
                    {titleText}
                </Pressable>
            ) : (
                titleText
            )}
        </View>
    );
}
