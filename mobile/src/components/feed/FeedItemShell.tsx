import React from "react";
import { Text, View } from "react-native";

import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { formatItemTimestamp } from "./dateGrouping";
import type { IFeedItem } from "./types";

interface IProps {
    item: IFeedItem;
    avatar: React.ReactNode;
    whoLine: React.ReactNode;
    subtitle?: string;
    children?: React.ReactNode;
}

const FeedItemShell: React.FC<IProps> = ({ item, avatar, whoLine, subtitle, children }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <View
            testID={`feed-item-${item.key}`}
            style={{
                flexDirection: "row",
                gap: 12,
                borderBottomWidth: 1,
                borderBottomColor: t.border,
                backgroundColor: t.card,
                paddingHorizontal: 16,
                paddingVertical: 18,
            }}
        >
            <View>{avatar}</View>
            <View style={{ flex: 1, minWidth: 0 }}>
                <View style={{ flexDirection: "row", alignItems: "baseline", justifyContent: "space-between", gap: 8 }}>
                    <Text
                        style={{
                            flex: 1,
                            fontFamily: "OpenSans-Regular",
                            fontSize: 15,
                            lineHeight: 21,
                            color: t.foreground,
                        }}
                    >
                        {whoLine}
                    </Text>
                    <Text style={{ fontFamily: "OpenSans-Regular", fontSize: 12, color: t.mutedForeground }}>
                        {formatItemTimestamp(item.occurred_at, item.kind)}
                    </Text>
                </View>
                {subtitle ? (
                    <Text
                        style={{
                            marginTop: 2,
                            fontFamily: "OpenSans-Regular",
                            fontSize: 12,
                            color: t.mutedForeground,
                        }}
                    >
                        {subtitle}
                    </Text>
                ) : null}
                {children}
            </View>
        </View>
    );
};

export default FeedItemShell;
