import React from "react";
import { Text, View } from "react-native";

import { cleanFeedSummary } from "../../../../app/frontend/components/feed/feedSummary";
import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { shortBillTitle } from "../../utils/billTitle";
import { Markdown, markdownExceedsLimit } from "../Markdown";
import { Pressable } from "../ui/Pressable";
import type { IFeedBill } from "./types";

// @lat: [[home-feed#Mobile summary excerpt]]
const SUMMARY_PREVIEW_CHARS = 280;

interface IProps {
    bill: IFeedBill;
    showSummary?: boolean;
    onPressBill: (billId: number) => void;
}

const FeedBillBlock: React.FC<IProps> = ({ bill, showSummary = false, onPressBill }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const displayTitle = shortBillTitle(bill.title);
    const hasSummary = showSummary && cleanFeedSummary(bill.summary) !== null;

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
                {hasSummary ? (
                    <View style={{ marginTop: 8 }}>
                        <Markdown
                            testID={`feed-bill-summary-${bill.id}`}
                            content={bill.summary}
                            maxChars={SUMMARY_PREVIEW_CHARS}
                            className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                        />
                        {markdownExceedsLimit(bill.summary, SUMMARY_PREVIEW_CHARS) ? (
                            <Text
                                accessibilityRole="link"
                                onPress={() => onPressBill(bill.id)}
                                style={{ marginTop: 4, fontFamily: "OpenSans-SemiBold", fontSize: 14, color: t.accent }}
                            >
                                {PARITY_COPY.bill.showMore}
                            </Text>
                        ) : null}
                    </View>
                ) : null}
                {hasSummary && bill.summary_ai_unreviewed ? (
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
                    {PARITY_COPY.feed.votedCount(bill.vote_count)}
                </Text>
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
