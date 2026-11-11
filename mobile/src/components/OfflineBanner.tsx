import React from "react";
import { View, Text } from "react-native";
import { WifiOff } from "lucide-react-native";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

export interface OfflineBannerProps {
    message?: string;
    testID?: string;
}

const DEFAULT_COPY = "You're offline — votes require a connection.";

export function OfflineBanner({ message, testID = "offline-banner" }: OfflineBannerProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    return (
        <View
            accessibilityRole="alert"
            accessibilityLabel={message ?? DEFAULT_COPY}
            testID={testID}
            style={{
                backgroundColor: t.warning,
                paddingHorizontal: 16,
                paddingVertical: 10,
                flexDirection: "row",
                alignItems: "center",
                justifyContent: "center",
                gap: 8,
            }}
        >
            <WifiOff size={16} color={t.warningForeground} strokeWidth={2} />
            <Text
                className="text-sm font-open-sans-semibold"
                style={{ color: t.warningForeground, flexShrink: 1, textAlign: "center" }}
            >
                {message ?? DEFAULT_COPY}
            </Text>
        </View>
    );
}

export default OfflineBanner;
