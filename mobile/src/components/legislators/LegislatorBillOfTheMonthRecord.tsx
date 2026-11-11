import React from "react";
import { Text, View } from "react-native";

import { SkeletonCard } from "../SkeletonCard";
import { StampedBadge } from "../StampedBadge";
import { Pressable } from "../ui/Pressable";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { PARITY_COPY } from "../../../../app/frontend/sway_constants/parityCopy";
import type { ILegislatorBillOfTheMonthVote } from "../../types/legislator";

interface IProps {
    votes: ILegislatorBillOfTheMonthVote[] | undefined;
    loading: boolean;
    error: Error | null;
    isSignedIn: boolean;
    onRetry: () => void;
    onSelectBill: (billId: number) => void;
}

type TVote = NonNullable<ILegislatorBillOfTheMonthVote["legislator_vote"]>;

const VOTE_LABEL: Record<TVote, string> = { FOR: "For", AGAINST: "Against", ABSTAIN: "Abstain" };

const ROW_LABEL_CLASS = "text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark";
const BADGE_ROW_STYLE = { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 8 } as const;

// @lat: [[legislator-botm-record#Release dates are read in UTC]]
export const formatReleaseMonth = (isoDate: string): string =>
    new Date(isoDate).toLocaleDateString("en-US", { month: "short", year: "numeric", timeZone: "UTC" });

// @lat: [[legislator-botm-record#Bill of the Month voting record on the legislator page]]
export const LegislatorBillOfTheMonthRecord: React.FC<IProps> = ({
    votes,
    loading,
    error,
    isSignedIn,
    onRetry,
    onSelectBill,
}) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (!votes && !loading && !error) return null;

    const voteColor = (vote: TVote | null): string => {
        if (vote === "FOR") return t.voteFor;
        if (vote === "AGAINST") return t.voteAgainst;
        return t.mutedForeground;
    };

    const renderBody = () => {
        if (!votes) {
            if (loading) {
                return <SkeletonCard testID="botm-record-skeleton" />;
            }
            return (
                <View testID="botm-record-error" style={BADGE_ROW_STYLE}>
                    <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                        {PARITY_COPY.legislators.votingRecordLoadError}
                    </Text>
                    <Pressable
                        variant="outline"
                        onPress={onRetry}
                        testID="botm-record-retry"
                        accessibilityLabel={PARITY_COPY.legislators.historyRetry}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.legislators.historyRetry}
                        </Text>
                    </Pressable>
                </View>
            );
        }
        if (votes.length === 0) {
            return (
                <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                    {PARITY_COPY.legislators.votingRecordEmpty}
                </Text>
            );
        }
        return votes.map((entry) => {
            const releaseMonth = formatReleaseMonth(entry.scheduled_release_date_utc);
            const externalId = entry.external_id.toUpperCase();
            return (
                <View
                    key={entry.bill_id}
                    testID={`botm-record-row-${entry.bill_id}`}
                    className="bg-surface-2-light dark:bg-surface-2-dark border border-border-light dark:border-border-dark rounded-xl px-3 py-3 gap-2"
                >
                    <Pressable
                        variant="ghost"
                        accessibilityRole="link"
                        accessibilityLabel={`${externalId}: ${entry.title}`}
                        onPress={() => onSelectBill(entry.bill_id)}
                        style={{ alignItems: "stretch", paddingHorizontal: 0, paddingVertical: 0 }}
                    >
                        <Text
                            className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                            style={{ textTransform: "uppercase", letterSpacing: 1.5 }}
                        >
                            {`${releaseMonth} · ${externalId}`}
                        </Text>
                        <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {entry.title}
                        </Text>
                    </Pressable>
                    <View style={BADGE_ROW_STYLE}>
                        <Text className={ROW_LABEL_CLASS}>{PARITY_COPY.legislators.legislatorVoteLabel}</Text>
                        <StampedBadge
                            testID={`botm-legislator-vote-${entry.bill_id}`}
                            color={voteColor(entry.legislator_vote)}
                            label={
                                entry.legislator_vote
                                    ? VOTE_LABEL[entry.legislator_vote]
                                    : PARITY_COPY.legislators.noRecordedVote
                            }
                        />
                    </View>
                    {isSignedIn ? (
                        <View style={BADGE_ROW_STYLE}>
                            <Text className={ROW_LABEL_CLASS}>{PARITY_COPY.legislators.yourVoteLabel}</Text>
                            <StampedBadge
                                testID={`botm-user-vote-${entry.bill_id}`}
                                color={voteColor(entry.user_vote)}
                                label={
                                    entry.user_vote ? VOTE_LABEL[entry.user_vote] : PARITY_COPY.legislators.notVotedYet
                                }
                            />
                            {entry.alignment && (
                                <StampedBadge
                                    testID={`botm-alignment-${entry.bill_id}`}
                                    color={entry.alignment === "agreed" ? t.success : t.destructive}
                                    label={
                                        entry.alignment === "agreed"
                                            ? PARITY_COPY.legislators.agreedBadge
                                            : PARITY_COPY.legislators.disagreedBadge
                                    }
                                />
                            )}
                        </View>
                    ) : null}
                </View>
            );
        });
    };

    return (
        <View
            testID="legislator-botm-record"
            className="bg-card-light dark:bg-card-dark border border-border-light dark:border-border-dark rounded-xl p-4 mb-4 gap-3"
        >
            <Text
                accessibilityRole="header"
                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                style={{ textTransform: "uppercase", letterSpacing: 2 }}
            >
                {PARITY_COPY.legislators.votingRecordHeading}
            </Text>
            {renderBody()}
        </View>
    );
};
