import React from "react";
import { Text, View } from "react-native";

import { cleanFeedSummary } from "../../../../app/frontend/components/feed/feedSummary";
import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { shortBillTitle } from "../../utils/billTitle";
import { Pressable } from "../ui/Pressable";
import type { IFeedBill } from "./types";

interface IProps {
    bill: IFeedBill;
    showSummary?: boolean;
    onPressBill: (billId: number) => void;
}

const FeedBillBlock: React.FC<IProps> = ({ bill, showSummary = false, onPressBill }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const displayTitle = shortBillTitle(bill.title);
    const cleanedSummary = showSummary ? cleanFeedSummary(bill.summary) : null;

    return (
        <View>
            <Pressable
                variant="ghost"
                onPress={() => onPressBill(bill.id)}
                testID={`feed-bill-card-${bill.id}`}
                accessibilityLabel={displayTitle}
                className="!items-start !justify-start !px-4 !py-3.5 !rounded-md"
                style={{
                    marginTop: 12,
                    borderWidth: 1,
                    borderColor: t.border,
                    backgroundColor: t.card,
                    width: "100%",
                }}
            >
                <Text style={{ fontFamily: "OpenSans-SemiBold", fontSize: 12, color: t.mutedForeground }}>
                    {bill.external_id}
                </Text>
                <Text
                    style={{
                        marginTop: 4,
                        fontFamily: "OpenSans-SemiBold",
                        fontSize: 16,
                        lineHeight: 22,
                        color: t.foreground,
                    }}
                >
                    {displayTitle}
                </Text>
                {cleanedSummary ? (
                    <Text
                        style={{
                            marginTop: 8,
                            fontFamily: "OpenSans-Light",
                            fontSize: 14,
                            lineHeight: 20,
                            color: t.mutedForeground,
                        }}
                    >
                        {cleanedSummary}
                    </Text>
                ) : null}
                {cleanedSummary && bill.summary_ai_unreviewed ? (
                    <Text
                        testID="ai-unreviewed-notice"
                        style={{
                            marginTop: 8,
                            fontFamily: "OpenSans-SemiBold",
                            fontSize: 12,
                            color: t.mutedForeground,
                        }}
                    >
                        {PARITY_COPY.bill.aiUnreviewedNotice}
                    </Text>
                ) : null}
            </Pressable>
            <View style={{ marginTop: 8, flexDirection: "row", alignItems: "center", gap: 12 }}>
                <Text
                    style={{
                        fontFamily: "OpenSans-Regular",
                        fontSize: 12,
                        color: t.mutedForeground,
                        fontVariant: ["tabular-nums"],
                    }}
                >
                    {PARITY_COPY.feed.viewedCount(bill.view_count)}
                </Text>
                <Text
                    style={{
                        fontFamily: "OpenSans-Regular",
                        fontSize: 12,
                        color: t.mutedForeground,
                        fontVariant: ["tabular-nums"],
                    }}
                >
                    {PARITY_COPY.feed.sharedCount(bill.share_count)}
                </Text>
            </View>
        </View>
    );
};

export default FeedBillBlock;
