import React from "react";
import { Text, View } from "react-native";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { LegislatorAgreeableScore } from "../hooks/useLegislators";

export interface ScoreTilesRowProps {
    score?: LegislatorAgreeableScore | null;
    testID?: string;
    className?: string;
}

export const ScoreTilesRow: React.FC<ScoreTilesRowProps> = ({ score, testID, className = "flex-row gap-3" }) => {
    if (!score) return null;

    const tiles = [
        {
            label: PARITY_COPY.legislators.scoreAgreed,
            value: Number(score.count_agreed ?? 0),
            color: "text-vote-for-light dark:text-vote-for-dark",
        },
        {
            label: PARITY_COPY.legislators.scoreDisagreed,
            value: Number(score.count_disagreed ?? 0),
            color: "text-vote-against-light dark:text-vote-against-dark",
        },
        {
            label: PARITY_COPY.legislators.scoreNoVote,
            value: Number(score.count_no_legislator_vote ?? 0),
            color: "text-foreground-light dark:text-foreground-dark",
        },
    ];

    return (
        <View testID={testID} className={className}>
            {tiles.map(({ label, value, color }) => (
                <View
                    key={label}
                    className="flex-1 bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl px-3 py-3"
                >
                    <Text
                        className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                        style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                    >
                        {label}
                    </Text>
                    <Text
                        className={`text-2xl font-open-sans-semibold ${color}`}
                        style={{ fontVariant: ["tabular-nums"] }}
                    >
                        {value}
                    </Text>
                </View>
            ))}
        </View>
    );
};

export default ScoreTilesRow;
