import React from "react";
import { Text, View } from "react-native";
import { Building2, Landmark, User } from "lucide-react-native";

import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { formatItemTimestamp } from "./dateGrouping";
import type { IFeedItem } from "./types";

const SUBJECT_ICONS = {
    locale: Landmark,
    legislator: User,
    organization: Building2,
};

interface IProps {
    item: IFeedItem;
    avatar: React.ReactNode;
    whoLine: React.ReactNode;
    subtitle?: string;
    subject?: keyof typeof SUBJECT_ICONS;
    children?: React.ReactNode;
}

const FeedItemShell: React.FC<IProps> = ({ item, avatar, whoLine, subtitle, subject, children }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const SubjectIcon = subject ? SUBJECT_ICONS[subject] : null;

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
                    <View style={{ flex: 1, flexDirection: "row", alignItems: "flex-start", gap: 6 }}>
                        {SubjectIcon ? (
                            <View style={{ marginTop: 4 }}>
                                <SubjectIcon size={14} color={t.mutedForeground} />
                            </View>
                        ) : null}
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
                    </View>
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
