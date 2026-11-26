// @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
// @lat: [[legislator-history-serialization#Why unvoted terms are rendered with distinct coverage indicators]]
import React, { useState } from "react";
import { Pressable, Text, View } from "react-native";
import { ChevronDown, ChevronUp, Vote } from "lucide-react-native";

import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { StampedBadge } from "../StampedBadge";
import { Card, CardHeader, CardTitle, CardContent } from "../ui/Card";
import { LegislatorChartsPanel } from "../LegislatorChartsPanel";
import { VoteComparisonPlaceholder } from "../VoteComparisonPlaceholder";
import { HistoricalRepairModal } from "./HistoricalRepairModal";
import { calculateAgreement, calculateGroupAgreement } from "../../types/legislator";
import type { ILegislatorTermCardProps } from "../../types/legislator";
import type { LegislatorRecord } from "../../hooks/useLegislators";

export function LegislatorTermCard({
    term,
    legislatorName,
    legislator,
    fallbackDistrictName,
    isLoggedIn = true,
    onPressExplanation,
    onSignInPress,
}: ILegislatorTermCardProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const [chartsOpen, setChartsOpen] = useState(false);
    const [repairModalOpen, setRepairModalOpen] = useState(false);

    const userCalc = calculateAgreement(term.user_score);
    const districtCalc = calculateGroupAgreement(term.district_score);
    const localeCalc = calculateGroupAgreement(term.locale_score);

    const legName = legislatorName ?? (legislator as LegislatorRecord)?.full_name ?? "Legislator";
    const districtTitle =
        term.district_name ?? fallbackDistrictName ?? (legislator as LegislatorRecord)?.district?.name ?? "District";
    const termWindowText = `${term.term_start_year}\u2013${term.term_end_year}`;

    return (
        <Card testID="legislator-term-card" className="mb-4">
            <CardHeader className="space-y-3 pb-3">
                <View className="flex-col gap-2">
                    <View className="space-y-1">
                        <CardTitle className="text-xl font-open-sans-semibold">{term.session_label}</CardTitle>
                        <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-muted-foreground-light dark:text-muted-foreground-dark">
                            {term.district_name ?? "At-Large"} · {termWindowText}
                        </Text>
                    </View>

                    <View className="flex-row flex-wrap items-center gap-2">
                        {term.active ? (
                            <StampedBadge label="Current Term" color={t.success} testID="term-active-badge" />
                        ) : (
                            <StampedBadge label="Ended" color={t.mutedForeground} testID="term-past-badge" />
                        )}

                        {term.is_executive ? (
                            <StampedBadge label="Executive Office" color={t.info} testID="term-card-executive-stamp" />
                        ) : null}

                        {term.correction_explanation ? (
                            <Pressable
                                onPress={() => {
                                    setRepairModalOpen(true);
                                    onPressExplanation?.(term.correction_explanation!, term);
                                }}
                                accessibilityRole="button"
                                accessibilityLabel="View score correction audit explanation"
                                testID="record-corrected-badge"
                            >
                                <StampedBadge label="Record Corrected" color={t.warning} />
                            </Pressable>
                        ) : null}
                    </View>
                </View>
            </CardHeader>

            <CardContent className="gap-4 pt-0">
                {isLoggedIn ? (
                    term.user_score ? (
                        <View
                            testID="term-user-score-tile"
                            className="bg-surface-2-light dark:bg-surface-2-dark border border-border-strong rounded-xl p-4 gap-2"
                        >
                            <View className="flex-row items-center justify-between">
                                <View className="flex-row items-center gap-2">
                                    <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-muted-foreground-light dark:text-muted-foreground-dark">
                                        Your Agreement
                                    </Text>
                                    <StampedBadge label="Personal" color={t.primary} />
                                </View>
                                <Text
                                    className="text-xl font-open-sans-bold tabular-nums text-primary-light dark:text-primary-dark"
                                    style={{ fontVariant: ["tabular-nums"] }}
                                >
                                    {userCalc.displayPct}
                                </Text>
                            </View>
                            <View className="flex-row flex-wrap gap-4 text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                <Text className="text-xs font-open-sans-semibold text-vote-for-light dark:text-vote-for-dark">
                                    {userCalc.agreed} Agreed
                                </Text>
                                <Text className="text-xs font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark">
                                    {userCalc.disagreed} Disagreed
                                </Text>
                                {userCalc.noVote > 0 ? (
                                    <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {userCalc.noVote} No Vote
                                    </Text>
                                ) : null}
                                {userCalc.abstained > 0 ? (
                                    <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {userCalc.abstained} Abstained
                                    </Text>
                                ) : null}
                            </View>
                        </View>
                    ) : (
                        <View
                            testID="unvoted-term-notice"
                            className="flex-row items-start gap-3 bg-surface-2-light dark:bg-surface-2-dark border border-border-soft-light dark:border-border-soft-dark rounded-xl p-4"
                        >
                            <Vote size={20} color={t.mutedForeground} />
                            <View className="flex-1 gap-1">
                                <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-foreground-light dark:text-foreground-dark">
                                    No Personal Votes Recorded
                                </Text>
                                <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark leading-normal">
                                    You have no votes on record for this term. Community agreement for this term is
                                    displayed below.
                                </Text>
                            </View>
                        </View>
                    )
                ) : (
                    <View
                        testID="unauthenticated-history-notice"
                        className="bg-surface-2-light dark:bg-surface-2-dark border border-dashed border-border-strong rounded-xl p-4 gap-3"
                    >
                        <View className="gap-1">
                            <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-foreground-light dark:text-foreground-dark">
                                Compare Your Votes
                            </Text>
                            <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark leading-normal">
                                Sign in or register with your address to see personal vote agreement against this
                                representative for this term.
                            </Text>
                        </View>
                        <Pressable
                            onPress={onSignInPress}
                            accessibilityRole="button"
                            accessibilityLabel="Sign in to compare votes"
                            className="min-h-[44px] bg-primary-light dark:bg-primary-dark rounded-xl items-center justify-center px-4 self-start"
                        >
                            <Text className="text-xs font-open-sans-bold uppercase tracking-wider text-white">
                                Sign in
                            </Text>
                        </Pressable>
                    </View>
                )}

                <View className="gap-3">
                    <View
                        testID="term-district-score-tile"
                        className="bg-surface-2-light dark:bg-surface-2-dark border border-border-strong rounded-xl p-4 gap-2"
                    >
                        <View className="flex-row items-center justify-between">
                            <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-muted-foreground-light dark:text-muted-foreground-dark">
                                {districtTitle} Agreement
                            </Text>
                            {districtCalc.suppressed ? null : (
                                <Text
                                    className="text-xl font-open-sans-bold tabular-nums text-foreground-light dark:text-foreground-dark"
                                    style={{ fontVariant: ["tabular-nums"] }}
                                >
                                    {districtCalc.displayPct}
                                </Text>
                            )}
                        </View>
                        {districtCalc.suppressed ? (
                            <VoteComparisonPlaceholder testID="term-district-score-suppressed" />
                        ) : (
                            <View className="flex-row flex-wrap gap-4 text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                <Text className="text-xs font-open-sans-semibold text-vote-for-light dark:text-vote-for-dark">
                                    {districtCalc.agreedPct}% Agreed
                                </Text>
                                <Text className="text-xs font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark">
                                    {districtCalc.disagreedPct}% Disagreed
                                </Text>
                                {districtCalc.noVotePct > 0 ? (
                                    <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {districtCalc.noVotePct}% No Vote
                                    </Text>
                                ) : null}
                            </View>
                        )}
                    </View>

                    <View
                        testID="term-locale-score-tile"
                        className="bg-surface-2-light dark:bg-surface-2-dark border border-border-strong rounded-xl p-4 gap-2"
                    >
                        <View className="flex-row items-center justify-between">
                            <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-muted-foreground-light dark:text-muted-foreground-dark">
                                Locale Agreement
                            </Text>
                            {localeCalc.suppressed ? null : (
                                <Text
                                    className="text-xl font-open-sans-bold tabular-nums text-foreground-light dark:text-foreground-dark"
                                    style={{ fontVariant: ["tabular-nums"] }}
                                >
                                    {localeCalc.displayPct}
                                </Text>
                            )}
                        </View>
                        {localeCalc.suppressed ? (
                            <VoteComparisonPlaceholder testID="term-locale-score-suppressed" />
                        ) : (
                            <View className="flex-row flex-wrap gap-4 text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                <Text className="text-xs font-open-sans-semibold text-vote-for-light dark:text-vote-for-dark">
                                    {localeCalc.agreedPct}% Agreed
                                </Text>
                                <Text className="text-xs font-open-sans-semibold text-vote-against-light dark:text-vote-against-dark">
                                    {localeCalc.disagreedPct}% Disagreed
                                </Text>
                                {localeCalc.noVotePct > 0 ? (
                                    <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {localeCalc.noVotePct}% No Vote
                                    </Text>
                                ) : null}
                            </View>
                        )}
                    </View>
                </View>

                {term.user_score || term.district_score || term.locale_score ? (
                    <View className="gap-3 pt-1">
                        <Pressable
                            onPress={() => setChartsOpen((v) => !v)}
                            accessibilityRole="button"
                            accessibilityLabel={chartsOpen ? "Hide term charts" : "Show term charts"}
                            testID={`term-charts-toggle-${term.id}`}
                            className="flex-row items-center gap-2 min-h-[44px] bg-surface-2-light dark:bg-surface-2-dark border border-border-strong rounded-xl px-3 self-start"
                        >
                            <Text className="text-xs font-open-sans-bold uppercase tracking-wider text-foreground-light dark:text-foreground-dark">
                                {chartsOpen ? "Hide term charts" : "Show term charts"}
                            </Text>
                            {chartsOpen ? (
                                <ChevronUp size={16} color={t.mutedForeground} />
                            ) : (
                                <ChevronDown size={16} color={t.mutedForeground} />
                            )}
                        </Pressable>

                        {chartsOpen ? (
                            <View testID={`term-charts-panel-${term.id}`} className="gap-3 pt-2">
                                {term.user_score ? (
                                    <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                        <LegislatorChartsPanel
                                            score={term.user_score}
                                            title={`Your agreement · ${term.session_label}`}
                                            testID={`term-chart-user-${term.id}`}
                                        />
                                    </View>
                                ) : null}
                                {term.district_score ? (
                                    <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                        <LegislatorChartsPanel
                                            group
                                            score={term.district_score}
                                            title={`${districtTitle} agreement · ${term.session_label}`}
                                            testID={`term-chart-district-${term.id}`}
                                        />
                                    </View>
                                ) : null}
                                {term.locale_score ? (
                                    <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                        <LegislatorChartsPanel
                                            group
                                            score={term.locale_score}
                                            title={`Locale agreement · ${term.session_label}`}
                                            testID={`term-chart-locale-${term.id}`}
                                        />
                                    </View>
                                ) : null}
                            </View>
                        ) : null}
                    </View>
                ) : null}
            </CardContent>

            {term.correction_explanation ? (
                <HistoricalRepairModal
                    explanation={term.correction_explanation}
                    term={term}
                    legislatorName={legName}
                    visible={repairModalOpen}
                    onClose={() => setRepairModalOpen(false)}
                />
            ) : null}
        </Card>
    );
}

export default LegislatorTermCard;
