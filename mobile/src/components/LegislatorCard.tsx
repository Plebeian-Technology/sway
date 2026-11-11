// @lat: [[mobile-legislator-components-design#LegislatorCard]]
import React, { useState } from "react";
import { Image, Text, View } from "react-native";
import { User } from "lucide-react-native";

import { Card, CardHeader, CardContent, CardFooter } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { LegislatorChartsPanel } from "./LegislatorChartsPanel";
import { StampedBadge } from "./StampedBadge";
import { ScoreTilesRow } from "./ScoreTilesRow";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import type { LegislatorAgreeableScore, LegislatorRecord } from "../hooks/useLegislators";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface LegislatorCardHistoryEntry {
    score: LegislatorAgreeableScore;
    termWindow: string;
}

export interface LegislatorCardProps {
    legislator: LegislatorRecord;
    onPress?: () => void;
    testID?: string;
    mode?: "current" | "lifetime";
    historyEntry?: LegislatorCardHistoryEntry;
}

export function LegislatorCard({ legislator, onPress, testID, mode = "current", historyEntry }: LegislatorCardProps) {
    const [chartsOpen, setChartsOpen] = useState(false);
    const [avatarFailed, setAvatarFailed] = useState(false);
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const score = historyEntry
        ? historyEntry.score
        : ((mode === "lifetime" ? legislator.lifetime_score : legislator.user_legislator_score) ?? null);
    const cardTestID = testID ?? `legislator-card-${legislator.id}`;
    const showImage = !!legislator.photo_url && !avatarFailed;

    return (
        <Card
            onPress={onPress}
            testID={cardTestID}
            accessibilityLabel={`Open profile for ${legislator.full_name ?? "legislator"}`}
            className="mb-3"
            accentColor={t.primary}
        >
            <CardHeader className="gap-3">
                {/* @lat: [[mobile-legislator-components-design#LegislatorCard#Avatar and name row]] */}
                <View className="flex-row items-center gap-3">
                    <View className="w-16 h-20 rounded-lg border border-border-light dark:border-border-dark bg-surface-2-light dark:bg-surface-2-dark items-center justify-center overflow-hidden">
                        {showImage ? (
                            <Image
                                source={{ uri: legislator.photo_url ?? undefined }}
                                accessibilityLabel={`${legislator.full_name ?? "Legislator"} avatar`}
                                className="w-full h-full"
                                resizeMode="cover"
                                onError={() => setAvatarFailed(true)}
                            />
                        ) : (
                            <User size={32} color={t.mutedIcon} testID={`${cardTestID}-avatar-fallback`} />
                        )}
                    </View>
                    <View className="flex-1">
                        <View className="flex-row items-center flex-wrap gap-2">
                            <Text className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {legislator.full_name ?? "Legislator"}
                            </Text>
                            {historyEntry ? (
                                // @lat: [[mobile-legislator-components-design#LegislatorCard]]
                                <StampedBadge
                                    testID={`${cardTestID}-ended-stamp`}
                                    label={PARITY_COPY.legislators.endedStamp}
                                    color={t.mutedForeground}
                                />
                            ) : null}
                        </View>
                        {legislator.title ? (
                            <Text
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mt-1"
                                style={{ textTransform: "uppercase", letterSpacing: 2.5 }}
                            >
                                {legislator.title}
                            </Text>
                        ) : null}
                        {historyEntry ? (
                            <Text
                                testID={`${cardTestID}-term-window`}
                                className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark mt-1"
                            >
                                {historyEntry.termWindow}
                            </Text>
                        ) : null}
                    </View>
                </View>
            </CardHeader>

            <CardContent>
                <ScoreTilesRow score={score} />
            </CardContent>

            <CardFooter>
                {/* @lat: [[mobile-legislator-components-design#LegislatorCard]] */}
                {score && !historyEntry ? (
                    <Pressable
                        variant="ghost"
                        onPress={() => setChartsOpen((v) => !v)}
                        accessibilityRole="button"
                        accessibilityLabel={
                            chartsOpen ? PARITY_COPY.legislators.hideCharts : PARITY_COPY.legislators.showCharts
                        }
                        accessibilityState={{ expanded: chartsOpen }}
                        testID={`${cardTestID}-charts-toggle`}
                    >
                        <Text
                            className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark"
                            style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                        >
                            {chartsOpen ? PARITY_COPY.legislators.hideCharts : PARITY_COPY.legislators.showCharts}
                        </Text>
                    </Pressable>
                ) : null}
            </CardFooter>

            {chartsOpen && score && !historyEntry ? (
                <LegislatorChartsPanel score={score} testID={`legislator-charts-panel-${legislator.id}`} />
            ) : null}
        </Card>
    );
}

export default LegislatorCard;
