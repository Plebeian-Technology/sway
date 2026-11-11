// @lat: [[mobile-chrome-sheets-design#UpdateBanner]]
import { useState } from "react";
import { View, Text, Pressable, Linking } from "react-native";
import { X } from "lucide-react-native";

import { useBootstrap } from "../state/BootstrapContext";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

const DOWNLOAD_URL = "https://sway.vote/download";

export function UpdateBanner() {
    const { needsUpdate } = useBootstrap();
    const [dismissed, setDismissed] = useState(false);
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (!needsUpdate || dismissed) return null;

    return (
        <View
            className="flex-row items-center justify-between px-4 py-3 bg-secondary-light dark:bg-secondary-dark border-b border-border-light dark:border-border-dark"
            accessibilityRole="alert"
            testID="update-banner"
        >
            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark flex-1">
                A new version of Sway is available.
            </Text>
            <Pressable
                onPress={() => {
                    void Linking.openURL(DOWNLOAD_URL);
                }}
                accessibilityRole="link"
                accessibilityLabel="Update"
                style={{ minHeight: 44, justifyContent: "center" }}
            >
                <Text className="text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark mx-3">
                    Update
                </Text>
            </Pressable>
            <Pressable
                onPress={() => setDismissed(true)}
                accessibilityRole="button"
                accessibilityLabel="Dismiss update banner"
                style={{
                    minHeight: 44,
                    minWidth: 44,
                    alignItems: "center",
                    justifyContent: "center",
                }}
            >
                <X color={t.mutedForeground} />
            </Pressable>
        </View>
    );
}
