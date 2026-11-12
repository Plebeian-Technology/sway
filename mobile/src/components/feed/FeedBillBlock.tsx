import React from "react";
import { Text, View } from "react-native";
import { Share2 } from "lucide-react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { Pressable } from "../ui/Pressable";
import type { IFeedBill, TFeedSupport } from "./types";

interface IBillBlockProps {
    bill: IFeedBill;
    showSummary?: boolean;
    onPressBill: (billId: number) => void;
}

export const FeedBillBlock: React.FC<IBillBlockProps> = ({ bill, showSummary = false, onPressBill }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <View>
            <Pressable
                variant="ghost"
                onPress={() => onPressBill(bill.id)}
                testID={`feed-bill-card-${bill.id}`}
                accessibilityLabel={bill.title}
                className="!items-start !justify-start !px-4 !py-3.5 !rounded-md"
                style={{
                    marginTop: 12,
                    borderWidth: 1,
                    borderColor: t.border,
                    backgroundColor: t.card,
                    width: "100%",
                }}
            >
                <Text style={{ fontSize: 12, fontWeight: "500", color: t.mutedForeground }}>{bill.external_id}</Text>
                <Text style={{ marginTop: 4, fontSize: 16, fontWeight: "600", lineHeight: 22, color: t.foreground }}>
                    {bill.title}
                </Text>
                {showSummary && bill.summary ? (
                    <Text style={{ marginTop: 8, fontSize: 14, lineHeight: 20, color: t.mutedForeground }}>
                        {bill.summary}
                    </Text>
                ) : null}
            </Pressable>
            <View style={{ marginTop: 8, flexDirection: "row", alignItems: "center", gap: 12 }}>
                <Text style={{ fontSize: 12, color: t.mutedForeground, fontVariant: ["tabular-nums"] }}>
                    {PARITY_COPY.feed.votedCount(bill.vote_count)}
                </Text>
                <Text style={{ fontSize: 12, color: t.mutedForeground, fontVariant: ["tabular-nums"] }}>
                    {PARITY_COPY.feed.viewedCount(bill.view_count)}
                </Text>
                <Text style={{ fontSize: 12, color: t.mutedForeground, fontVariant: ["tabular-nums"] }}>
                    {PARITY_COPY.feed.sharedCount(bill.share_count)}
                </Text>
            </View>
        </View>
    );
};

const UserVoteStatus: React.FC<{ userSupport: TFeedSupport }> = ({ userSupport }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (userSupport === "FOR") {
        return (
            <Text style={{ marginRight: "auto", fontSize: 14, color: t.mutedForeground }}>
                You voted <Text style={{ fontWeight: "600", color: t.voteFor }}>{PARITY_COPY.feed.voteLabels.for}</Text>
            </Text>
        );
    }
    if (userSupport === "AGAINST") {
        return (
            <Text style={{ marginRight: "auto", fontSize: 14, color: t.mutedForeground }}>
                You voted{" "}
                <Text style={{ fontWeight: "600", color: t.voteAgainst }}>{PARITY_COPY.feed.voteLabels.against}</Text>
            </Text>
        );
    }
    return (
        <Text style={{ marginRight: "auto", fontSize: 14, color: t.mutedForeground }}>
            {PARITY_COPY.feed.voteLabels.youAbstained}
        </Text>
    );
};

interface IActionsProps {
    bill: IFeedBill;
    userSupport: TFeedSupport | null;
    onPressBill: (billId: number) => void;
    onShareBill: (bill: IFeedBill) => void;
}

export const FeedBillActions: React.FC<IActionsProps> = ({ bill, userSupport, onPressBill, onShareBill }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    return (
        <View style={{ marginTop: 14, flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 10 }}>
            {userSupport === null ? (
                <Pressable
                    onPress={() => onPressBill(bill.id)}
                    testID={`feed-go-vote-${bill.id}`}
                    accessibilityLabel={PARITY_COPY.feed.voteLabels.goVote}
                    className="!rounded-md !px-4"
                >
                    <Text style={{ fontSize: 14, fontWeight: "600", color: t.primaryForeground }}>
                        {PARITY_COPY.feed.voteLabels.goVote}
                    </Text>
                </Pressable>
            ) : (
                <UserVoteStatus userSupport={userSupport} />
            )}
            <Pressable
                variant="outline"
                onPress={() => onShareBill(bill)}
                testID={`feed-share-bill-${bill.id}`}
                accessibilityLabel={PARITY_COPY.bill.shareBill}
                className="!rounded-md !px-3.5"
                style={{ flexDirection: "row", gap: 6 }}
            >
                <Share2 size={16} color={t.accent} />
                <Text style={{ fontSize: 14, fontWeight: "600", color: t.accent }}>{PARITY_COPY.bill.shareBill}</Text>
            </Pressable>
        </View>
    );
};
