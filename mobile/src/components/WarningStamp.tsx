import React from "react";
import { Text, View } from "react-native";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

// @lat: [[news-mobile-testimony#Clear visual demarcation and distinction from organization positions]]

export interface WarningStampProps {
    label: string;
    testID?: string;
}

const FILL_ALPHA_HEX = { light: "0f", dark: "26" } as const;
const BORDER_ALPHA_HEX = "66";

export function WarningStamp({ label, testID }: WarningStampProps) {
    const { colorScheme } = useTheme();
    const warning = swayTokens[colorScheme].warning;

    return (
        <View
            testID={testID}
            accessibilityRole="text"
            className="border px-2 py-0.5 rounded-sm"
            style={{
                backgroundColor: `${warning}${FILL_ALPHA_HEX[colorScheme]}`,
                borderColor: `${warning}${BORDER_ALPHA_HEX}`,
            }}
        >
            <Text className="text-xs font-open-sans-semibold" style={{ color: warning }}>
                {label}
            </Text>
        </View>
    );
}

export default WarningStamp;
