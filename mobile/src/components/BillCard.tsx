// @lat: [[mobile-bill-surface-components-design#BillCard]]
import React from "react";
import { Text, View } from "react-native";
import { Card } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { readableForeground } from "./StampedBadge";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { billHeadline } from "../utils/billTitle";
import { isVoteComparisonSuppressed } from "../utils/districtVotes";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface BillCardBill {
    id: number;
    bill_number?: string;
    title: string;
    headline?: string;
    label?: string;
    status?: string;
    status_color?: string;
    external_id?: string;
    category?: string;
    summary?: string | null;
    user_vote?: { support?: string | null };
    bill_score?: {
        for?: number | null;
        against?: number | null;
        comparison_suppressed?: boolean | null;
        voters_needed?: number | null;
    };
    link?: string;
}

export interface BillCardProps {
    bill: BillCardBill;
    onPress: () => void;
    testID?: string;
}

const SUMMARY_EXCERPT_CHARS = 160;

export function BillCard({ bill, onPress, testID }: BillCardProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const headline = bill.headline ?? billHeadline(bill.title);
    const summaryClean = (bill.summary ?? "").replace(/NEWLINE|ENDING/g, " ").trim();
    const summaryExcerpt = summaryClean
        ? summaryClean.slice(0, SUMMARY_EXCERPT_CHARS) + (summaryClean.length > SUMMARY_EXCERPT_CHARS ? "…" : "")
        : "Open the bill to review the full summary, vote totals, and arguments.";

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    const comparisonSuppressed = isVoteComparisonSuppressed(bill.bill_score);
    const votersNeeded = bill.bill_score?.voters_needed;
    const forCount = bill.bill_score?.for ?? 0;
    const againstCount = bill.bill_score?.against ?? 0;
    const titleizedCategory = bill.category ? bill.category.charAt(0).toUpperCase() + bill.category.slice(1) : null;

    const support = bill.user_vote?.support ? String(bill.user_vote.support).toLowerCase() : null;
    const voteFill = support === "for" ? t.voteFor : support === "against" ? t.voteAgainst : t.primary;
    const accentColor = support ? voteFill : t.primary;

    return (
        <Card
            onPress={onPress}
            testID={testID ?? `bill-card-${bill.id}`}
            accessibilityLabel={`Open bill ${headline}`}
            className="mb-3"
            accentColor={accentColor}
        >
            <View className="flex-row flex-wrap gap-2 items-center">
                {bill.external_id ? (
                    <View className="bg-accent-light dark:bg-accent-dark px-2 py-0.5 rounded">
                        <Text
                            className="text-xs font-open-sans-semibold text-accent-foreground-light dark:text-accent-foreground-dark"
                            style={{ textTransform: "uppercase", letterSpacing: 1.2 }}
                        >
                            {bill.external_id}
                        </Text>
                    </View>
                ) : null}
                {titleizedCategory ? (
                    <View className="bg-surface-3-light dark:bg-surface-3-dark px-2 py-0.5 rounded">
                        <Text className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark">
                            {titleizedCategory}
                        </Text>
                    </View>
                ) : null}
                {support ? (
                    <View className="px-2 py-0.5 rounded" style={{ backgroundColor: voteFill }} testID="user-vote-pill">
                        <Text
                            className="text-xs font-open-sans-semibold"
                            style={{
                                color: readableForeground(voteFill),
                                textTransform: "uppercase",
                                letterSpacing: 1.2,
                            }}
                        >
                            {`You voted: ${bill.user_vote?.support}`}
                        </Text>
                    </View>
                ) : null}
            </View>

            <Text
                className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark leading-tight"
                numberOfLines={3}
            >
                {headline}
            </Text>
            <Text
                className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                numberOfLines={2}
            >
                {summaryExcerpt}
            </Text>

            <View className="flex-row items-center gap-2">
                {comparisonSuppressed ? (
                    <Text
                        testID={`bill-card-${bill.id}-comparison-suppressed`}
                        className="flex-1 text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {typeof votersNeeded === "number" && votersNeeded > 0
                            ? PARITY_COPY.bill.voteComparisonPlaceholder.votersNeeded(votersNeeded)
                            : PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes}
                    </Text>
                ) : (
                    <>
                        <View className="flex-row items-baseline gap-1.5 bg-surface-3-light dark:bg-surface-3-dark rounded-lg px-3 py-1.5">
                            <Text
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                                style={{ textTransform: "uppercase", letterSpacing: 1.2 }}
                            >
                                For
                            </Text>
                            <Text
                                className="text-lg font-open-sans-semibold text-vote-for-light dark:text-vote-for-dark"
                                style={{ fontVariant: ["tabular-nums"] }}
                                testID={`bill-card-${bill.id}-for-count`}
                            >
                                {forCount}
                            </Text>
                        </View>
                        <View className="flex-row items-baseline gap-1.5 bg-surface-3-light dark:bg-surface-3-dark rounded-lg px-3 py-1.5">
                            <Text
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                                style={{ textTransform: "uppercase", letterSpacing: 1.2 }}
                            >
                                Against
                            </Text>
                            <Text
                                className="text-lg font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark"
                                style={{ fontVariant: ["tabular-nums"] }}
                                testID={`bill-card-${bill.id}-against-count`}
                            >
                                {againstCount}
                            </Text>
                        </View>
                    </>
                )}
                <View className="flex-1 items-end">
                    <Pressable
                        onPress={onPress}
                        accessibilityLabel="Open bill"
                        accessibilityRole="button"
                        variant="default"
                        testID={`bill-card-${bill.id}-open-btn`}
                    >
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            Open bill
                        </Text>
                    </Pressable>
                </View>
            </View>
        </Card>
    );
}

export default BillCard;
