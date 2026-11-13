import React from "react";
import { Text, View } from "react-native";
import { Share2 } from "lucide-react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { Pressable } from "../ui/Pressable";
import type { IFeedBill, TFeedSupport } from "./types";

interface IProps {
    bill: IFeedBill;
    userSupport: TFeedSupport | null;
    onPressBill: (billId: number) => void;
    onShareBill: (bill: IFeedBill) => void;
}

const FeedBillActions: React.FC<IProps> = ({ bill, userSupport, onPressBill, onShareBill }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const renderUserVoteStatus = (support: TFeedSupport) => {
        if (support === "FOR") {
            return (
                <Text
                    style={{
                        marginRight: "auto",
                        fontFamily: "OpenSans-Regular",
                        fontSize: 14,
                        color: t.mutedForeground,
                    }}
                >
                    {PARITY_COPY.feed.voteLabels.youVotedPrefix}
                    <Text style={{ fontFamily: "OpenSans-SemiBold", color: t.voteFor }}>
                        {PARITY_COPY.feed.voteLabels.for}
                    </Text>
                </Text>
            );
        }
        if (support === "AGAINST") {
            return (
                <Text
                    style={{
                        marginRight: "auto",
                        fontFamily: "OpenSans-Regular",
                        fontSize: 14,
                        color: t.mutedForeground,
                    }}
                >
                    {PARITY_COPY.feed.voteLabels.youVotedPrefix}
                    <Text style={{ fontFamily: "OpenSans-SemiBold", color: t.voteAgainst }}>
                        {PARITY_COPY.feed.voteLabels.against}
                    </Text>
                </Text>
            );
        }
        return (
            <Text
                style={{
                    marginRight: "auto",
                    fontFamily: "OpenSans-Regular",
                    fontSize: 14,
                    color: t.mutedForeground,
                }}
            >
                {PARITY_COPY.feed.voteLabels.youAbstained}
            </Text>
        );
    };

    return (
        <View style={{ marginTop: 14, flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 10 }}>
            {userSupport === null ? (
                <Pressable
                    onPress={() => onPressBill(bill.id)}
                    testID={`feed-go-vote-${bill.id}`}
                    accessibilityLabel={PARITY_COPY.feed.voteLabels.goVote}
                    className="!rounded-md !px-4"
                >
                    <Text style={{ fontFamily: "OpenSans-SemiBold", fontSize: 14, color: t.primaryForeground }}>
                        {PARITY_COPY.feed.voteLabels.goVote}
                    </Text>
                </Pressable>
            ) : (
                renderUserVoteStatus(userSupport)
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
                <Text style={{ fontFamily: "OpenSans-SemiBold", fontSize: 14, color: t.accent }}>
                    {PARITY_COPY.bill.shareBill}
                </Text>
            </Pressable>
        </View>
    );
};

export default FeedBillActions;
