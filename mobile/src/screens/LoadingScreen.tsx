// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator]]
import React from "react";
import { ActivityIndicator, Image, View } from "react-native";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

interface IProps {
    testID?: string;
}

const LoadingScreen: React.FC<IProps> = ({ testID }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    return (
        <View
            className="flex-1 items-center justify-center gap-6 bg-dominant-light dark:bg-dominant-dark"
            testID={testID}
        >
            <Image
                // oxlint-disable-next-line @typescript-eslint/no-require-imports
                source={require("../../assets/sway-logo.png")}
                accessibilityLabel="Sway"
                resizeMode="contain"
                style={{ width: 120, height: 120 }}
            />
            <ActivityIndicator color={t.primary} accessibilityLabel="Loading" />
        </View>
    );
};

export default LoadingScreen;
