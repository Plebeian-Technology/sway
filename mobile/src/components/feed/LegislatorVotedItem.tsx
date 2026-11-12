import React from "react";
import { Text, View } from "react-native";
import { AlertTriangle, Check, CheckCircle2, Minus, X } from "lucide-react-native";

import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { LegislatorAvatar } from "./FeedAvatar";
import { FeedBillActions, FeedBillBlock } from "./FeedBillBlock";
import FeedItemShell from "./FeedItemShell";
import type { IFeedBill, IFeedItem, TFeedSupport } from "./types";

interface IProps {
    item: IFeedItem;
    onPressBill: (billId: number) => void;
    onShareBill: (bill: IFeedBill) => void;
}

const VoteValue: React.FC<{ support: TFeedSupport; align?: "left" | "right" }> = ({ support, align = "left" }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const justify = align === "right" ? "flex-end" : "flex-start";

    if (support === "FOR") {
        return (
            <View style={{ marginTop: 2, flexDirection: "row", alignItems: "center", justifyContent: justify, gap: 4 }}>
                <Check size={16} color={t.voteFor} />
                <Text style={{ fontSize: 15, fontWeight: "700", color: t.voteFor }}>
                    {PARITY_COPY.feed.voteLabels.for}
                </Text>
            </View>
        );
    }
    if (support === "AGAINST") {
        return (
            <View style={{ marginTop: 2, flexDirection: "row", alignItems: "center", justifyContent: justify, gap: 4 }}>
                <X size={16} color={t.voteAgainst} />
                <Text style={{ fontSize: 15, fontWeight: "700", color: t.voteAgainst }}>
                    {PARITY_COPY.feed.voteLabels.against}
                </Text>
            </View>
        );
    }
    return (
        <View style={{ marginTop: 2, flexDirection: "row", alignItems: "center", justifyContent: justify, gap: 4 }}>
            <Minus size={16} color={t.mutedForeground} />
            <Text style={{ fontSize: 15, fontWeight: "700", color: t.mutedForeground }}>
                {PARITY_COPY.feed.voteLabels.abstain}
            </Text>
        </View>
    );
};

const InlineSupportWord: React.FC<{ support: TFeedSupport }> = ({ support }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (support === "FOR") {
        return <Text style={{ fontWeight: "600", color: t.voteFor }}>{PARITY_COPY.feed.voteLabels.for}</Text>;
    }
    if (support === "AGAINST") {
        return <Text style={{ fontWeight: "600", color: t.voteAgainst }}>{PARITY_COPY.feed.voteLabels.against}</Text>;
    }
    return <Text style={{ fontWeight: "600", color: t.mutedForeground }}>{PARITY_COPY.feed.voteLabels.abstain}</Text>;
};

const LegislatorVotedItem: React.FC<IProps> = ({ item, onPressBill, onShareBill }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const legislator = item.legislator;
    const localeName = item.sway_locale?.name ?? "";

    if (!legislator) {
        return null;
    }

    const subtitle = [legislator.title, legislator.district_name, localeName].filter(Boolean).join(", ");

    const renderWhoLine = () => {
        if (item.user_support) {
            return (
                <>
                    <Text style={{ fontWeight: "700" }}>{legislator.full_name}</Text>{" "}
                    {PARITY_COPY.feed.legislatorVotedWithUser}
                </>
            );
        }

        if (item.legislator_support === "ABSTAIN") {
            return (
                <>
                    <Text style={{ fontWeight: "700" }}>{legislator.full_name}</Text>{" "}
                    {PARITY_COPY.feed.legislatorAbstainedOnLocaleBill(localeName)}
                </>
            );
        }

        if (item.legislator_support === "FOR" || item.legislator_support === "AGAINST") {
            return (
                <>
                    <Text style={{ fontWeight: "700" }}>{legislator.full_name}</Text> voted{" "}
                    <InlineSupportWord support={item.legislator_support} /> a {localeName} bill
                </>
            );
        }

        return <Text style={{ fontWeight: "700" }}>{legislator.full_name}</Text>;
    };

    return (
        <FeedItemShell
            item={item}
            avatar={<LegislatorAvatar legislator={legislator} />}
            whoLine={renderWhoLine()}
            subtitle={subtitle || undefined}
        >
            {item.bill ? <FeedBillBlock bill={item.bill} onPressBill={onPressBill} /> : null}

            {item.user_support && item.legislator_support ? (
                <View
                    style={{
                        marginTop: 12,
                        flexDirection: "row",
                        alignItems: "stretch",
                        overflow: "hidden",
                        borderRadius: 8,
                        borderWidth: 1,
                        borderColor: t.border,
                    }}
                >
                    <View
                        style={{ flex: 1, backgroundColor: t.background, paddingHorizontal: 12, paddingVertical: 12 }}
                    >
                        <Text style={{ fontSize: 12, color: t.mutedForeground }}>
                            {PARITY_COPY.feed.voteLabels.you}
                        </Text>
                        <VoteValue support={item.user_support} />
                    </View>

                    {item.agreement === "agree" ? (
                        <View
                            style={{
                                flexDirection: "row",
                                alignItems: "center",
                                gap: 4,
                                borderLeftWidth: 1,
                                borderRightWidth: 1,
                                borderColor: t.border,
                                backgroundColor: t.successForeground,
                                paddingHorizontal: 10,
                            }}
                        >
                            <CheckCircle2 size={14} color={t.success} />
                            <Text style={{ fontSize: 12, fontWeight: "600", color: t.success }}>
                                {PARITY_COPY.feed.voteLabels.agree}
                            </Text>
                        </View>
                    ) : null}

                    {item.agreement === "differ" ? (
                        <View
                            style={{
                                flexDirection: "row",
                                alignItems: "center",
                                gap: 4,
                                borderLeftWidth: 1,
                                borderRightWidth: 1,
                                borderColor: t.border,
                                backgroundColor: t.warningForeground,
                                paddingHorizontal: 10,
                            }}
                        >
                            <AlertTriangle size={14} color={t.warning} />
                            <Text style={{ fontSize: 12, fontWeight: "600", color: t.warning }}>
                                {PARITY_COPY.feed.voteLabels.differ}
                            </Text>
                        </View>
                    ) : null}

                    {item.agreement === null ? <View style={{ borderLeftWidth: 1, borderColor: t.border }} /> : null}

                    <View
                        style={{ flex: 1, backgroundColor: t.background, paddingHorizontal: 12, paddingVertical: 12 }}
                    >
                        <Text numberOfLines={1} style={{ fontSize: 12, color: t.mutedForeground, textAlign: "right" }}>
                            {legislator.full_name}
                        </Text>
                        <VoteValue support={item.legislator_support} align="right" />
                    </View>
                </View>
            ) : null}

            {item.bill ? (
                <FeedBillActions
                    bill={item.bill}
                    userSupport={item.user_support}
                    onPressBill={onPressBill}
                    onShareBill={onShareBill}
                />
            ) : null}
        </FeedItemShell>
    );
};

export default LegislatorVotedItem;
