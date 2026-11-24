// @lat: [[mobile-bill-surface-components-design#BillScoreBar]]
import React, { useEffect } from "react";
import { View, Text } from "react-native";
import Animated, { useSharedValue, useAnimatedStyle, withTiming, Easing } from "react-native-reanimated";

import { CardTitle } from "./ui/Card";
import { formatVoteCount, isVoteComparisonSuppressed } from "../utils/districtVotes";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

interface BillScore {
    for?: number | null;
    against?: number | null;
    comparison_suppressed?: boolean | null;
}

export interface BillScoreBarProps {
    bill_score?: BillScore | null;
    testID?: string;
}

export function BillScoreBar({ bill_score, testID }: BillScoreBarProps) {
    const forCount = bill_score?.for ?? 0;
    const againstCount = bill_score?.against ?? 0;
    const total = forCount + againstCount;
    const forPct = total ? Math.round((forCount / total) * 100) : 0;
    const againstPct = total ? 100 - forPct : 0;
    const title = PARITY_COPY.bill.content.howOthersVoted;

    // @lat: [[mobile-bill-surface-components-design#BillScoreBar]]
    const forW = useSharedValue(forPct);
    const againstW = useSharedValue(againstPct);
    useEffect(() => {
        const cfg = { duration: 500, easing: Easing.out(Easing.cubic) };
        forW.value = withTiming(forPct, cfg);
        againstW.value = withTiming(againstPct, cfg);
    }, [forPct, againstPct, forW, againstW]);
    const forStyle = useAnimatedStyle(() => ({ width: `${forW.value}%`, height: "100%" }));
    const againstStyle = useAnimatedStyle(() => ({ width: `${againstW.value}%`, height: "100%" }));

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    if (isVoteComparisonSuppressed(bill_score)) return null;

    return (
        <View
            testID={testID ?? "bill-score-bar"}
            className="gap-2"
            accessible
            accessibilityRole="summary"
            accessibilityLabel={
                total
                    ? `${title}: ${forPct} percent for, ${againstPct} percent against, ${formatVoteCount(total)} total votes`
                    : `${title}: ${PARITY_COPY.bill.noVotesYet}`
            }
        >
            <CardTitle>{title}</CardTitle>
            <View
                testID="bill-score-bar-track"
                className="flex-row items-center overflow-hidden rounded-md bg-muted-light dark:bg-border-dark"
                style={{ height: 12 }}
            >
                <Animated.View
                    testID="bill-score-bar-for"
                    style={forStyle}
                    className="bg-vote-for-light dark:bg-vote-for-dark"
                />
                <Animated.View
                    testID="bill-score-bar-against"
                    style={againstStyle}
                    className="bg-vote-against-light dark:bg-vote-against-dark"
                />
            </View>
            {total ? (
                <View className="flex-row justify-between">
                    <Text
                        className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                        style={{ fontVariant: ["tabular-nums"] }}
                    >
                        {`For: ${formatVoteCount(forCount)} (${forPct}%)`}
                    </Text>
                    <Text
                        className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                        style={{ fontVariant: ["tabular-nums"] }}
                    >
                        {`Against: ${formatVoteCount(againstCount)} (${againstPct}%)`}
                    </Text>
                </View>
            ) : (
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {PARITY_COPY.bill.noVotesYet}
                </Text>
            )}
        </View>
    );
}

export default BillScoreBar;
