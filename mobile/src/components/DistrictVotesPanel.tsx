// @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { CardTitle } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import {
    districtMajority,
    formatVoteCount,
    representativesText,
    type DistrictVoteRow,
    type DistrictVotes,
} from "../utils/districtVotes";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface DistrictVotesPanelProps {
    votes: DistrictVotes;
    userVoteSupport?: "for" | "against" | null;
    testID?: string;
}

const COLLAPSED_ROWS = 8;
const LABEL_MIN_WIDTH = 72;
const COUNT_MIN_WIDTH = 52;
const TRACK_COLOR = "bg-muted-light dark:bg-border-dark";

const spokenName = (row: DistrictVoteRow): string => (row.isReaderDistrict ? `${row.label}, your district` : row.label);

const spokenVotesName = (row: DistrictVoteRow): string => {
    const representatives = representativesText(row);
    return representatives ? `${spokenName(row)} (${representatives})` : spokenName(row);
};

const spokenNet = (net: number): string =>
    net > 0 ? `plus ${formatVoteCount(net)}` : net < 0 ? `minus ${formatVoteCount(-net)}` : "even";

const signedNet = (net: number): string => `${net > 0 ? "+" : ""}${formatVoteCount(net)}`;

const alignmentStatement = (row: DistrictVoteRow, support: "for" | "against" | null | undefined): string | null => {
    if (!support) return null;
    const majority = districtMajority(row);
    if (majority === null) return "Your district has no recorded votes yet.";
    if (majority === "tie") return "Your district is evenly split.";
    return majority === support
        ? "Your vote matches your district's majority."
        : "Your vote differs from your district's majority.";
};

const SectionLabel: React.FC<{ children: string }> = ({ children }) => (
    <Text
        className="text-xs font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark"
        style={{ letterSpacing: 1.5 }}
    >
        {children}
    </Text>
);

const Legend: React.FC<{ testID: string; items: { label: string; className: string }[] }> = ({ testID, items }) => (
    <View testID={testID} className="flex-row flex-wrap items-center gap-x-4 gap-y-1">
        {items.map((item) => (
            <View key={item.label} className="flex-row items-center gap-2">
                <View className={`h-3 w-3 rounded-sm ${item.className}`} />
                <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {item.label}
                </Text>
            </View>
        ))}
    </View>
);

const RowLabel: React.FC<{ row: DistrictVoteRow }> = ({ row }) => (
    <Text
        className={
            row.isReaderDistrict
                ? "text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark"
                : "text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
        }
        style={{ minWidth: LABEL_MIN_WIDTH }}
    >
        {row.label}
    </Text>
);

const RowRepresentatives: React.FC<{ row: DistrictVoteRow }> = ({ row }) => {
    const representatives = representativesText(row);
    if (!representatives) return null;
    return (
        <Text
            testID={`district-votes-names-${row.number}`}
            numberOfLines={2}
            ellipsizeMode="tail"
            className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
        >
            {representatives}
        </Text>
    );
};

const CountText: React.FC<{ children: string }> = ({ children }) => (
    <Text
        className="text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
        style={{ minWidth: COUNT_MIN_WIDTH, textAlign: "right", fontVariant: ["tabular-nums"] }}
    >
        {children}
    </Text>
);

const BarLine: React.FC<{
    testID: string;
    trackTestID: string;
    pct: number;
    colorClassName: string;
    count: number;
}> = ({ testID, trackTestID, pct, colorClassName, count }) => (
    <View className="flex-row items-center gap-2">
        <View testID={trackTestID} className={`h-2.5 flex-1 overflow-hidden rounded-full ${TRACK_COLOR}`}>
            <View testID={testID} className={colorClassName} style={{ width: `${pct}%`, height: "100%" }} />
        </View>
        <CountText>{formatVoteCount(count)}</CountText>
    </View>
);

const ReaderDistrictBlock: React.FC<{
    row: DistrictVoteRow;
    userVoteSupport: "for" | "against" | null | undefined;
}> = ({ row, userVoteSupport }) => {
    const { colorScheme } = useTheme();
    const statement = alignmentStatement(row, userVoteSupport);
    const tally =
        row.total > 0
            ? `${formatVoteCount(row.forCount)} for, ${formatVoteCount(row.againstCount)} against`
            : PARITY_COPY.bill.noVotesYet;

    return (
        <View
            testID="district-votes-reader"
            accessible
            accessibilityLabel={`Your district, ${row.label}: ${tally}.${statement ? ` ${statement}` : ""}`}
            className="gap-2 rounded-lg px-3 py-3"
            style={{ backgroundColor: swayTokens[colorScheme].surface3 }}
        >
            <SectionLabel>Your district</SectionLabel>
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {row.label}
            </Text>
            {row.total > 0 ? (
                <>
                    <View
                        testID="district-votes-reader-track"
                        className={`h-2.5 flex-row overflow-hidden rounded-full ${TRACK_COLOR}`}
                    >
                        <View
                            className="bg-vote-for-light dark:bg-vote-for-dark"
                            style={{ width: `${row.forPct}%`, height: "100%" }}
                        />
                        <View
                            className="bg-vote-against-light dark:bg-vote-against-dark"
                            style={{ width: `${100 - row.forPct}%`, height: "100%" }}
                        />
                    </View>
                    <View
                        testID="district-votes-reader-tally"
                        className="flex-row flex-wrap justify-between gap-x-4 gap-y-1"
                    >
                        <Text
                            className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                            style={{ fontVariant: ["tabular-nums"] }}
                        >
                            {`For: ${formatVoteCount(row.forCount)} (${row.forPct}%)`}
                        </Text>
                        <Text
                            className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark"
                            style={{ fontVariant: ["tabular-nums"] }}
                        >
                            {`Against: ${formatVoteCount(row.againstCount)} (${100 - row.forPct}%)`}
                        </Text>
                    </View>
                </>
            ) : null}
            {row.total === 0 && !statement ? (
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {PARITY_COPY.bill.noVotesYet}
                </Text>
            ) : null}
            {statement ? (
                <Text
                    testID="district-votes-alignment"
                    className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    {statement}
                </Text>
            ) : null}
        </View>
    );
};

export function DistrictVotesPanel({ votes, userVoteSupport, testID }: DistrictVotesPanelProps) {
    const { colorScheme } = useTheme();
    const [expanded, setExpanded] = useState(false);

    if (!votes.hasVotes) return null;

    const { rows, readerRows, maxVotes, maxAbsNet } = votes;
    const highlight = swayTokens[colorScheme].surface3;
    const visibleRows = expanded ? rows : rows.filter((row, index) => index < COLLAPSED_ROWS || row.isReaderDistrict);
    const hiddenCount = rows.length - visibleRows.length;
    const canToggle = rows.length > COLLAPSED_ROWS && (expanded || hiddenCount > 0);
    const hiddenSentence =
        hiddenCount > 0 ? ` ${hiddenCount} more ${hiddenCount === 1 ? "district is" : "districts are"} not shown.` : "";

    const votesLabel = `Votes by district. ${visibleRows
        .map(
            (row) =>
                `${spokenVotesName(row)}: ${formatVoteCount(row.forCount)} for, ${formatVoteCount(row.againstCount)} against.`,
        )
        .join(" ")}${hiddenSentence}`;
    const netLabel = `Net votes by district, for minus against. ${visibleRows
        .map((row) => `${spokenName(row)}: ${spokenNet(row.net)}.`)
        .join(" ")}${hiddenSentence}`;

    return (
        <View testID={testID ?? "district-votes-panel"} className="gap-4">
            <CardTitle>How districts voted</CardTitle>

            {readerRows.map((row) => (
                <ReaderDistrictBlock key={row.key} row={row} userVoteSupport={userVoteSupport} />
            ))}

            <View testID="district-votes-chart" accessible accessibilityRole="image" accessibilityLabel={votesLabel}>
                <View className="gap-2">
                    <SectionLabel>Votes by district</SectionLabel>
                    {visibleRows.map((row) => (
                        <View
                            key={row.key}
                            testID={`district-votes-row-${row.number}`}
                            className="flex-row items-center gap-3 rounded-md px-2 py-1"
                            style={row.isReaderDistrict ? { backgroundColor: highlight } : undefined}
                        >
                            <RowLabel row={row} />
                            <View testID={`district-votes-bars-${row.number}`} className="flex-1 gap-1">
                                <BarLine
                                    testID={`district-votes-for-fill-${row.number}`}
                                    trackTestID={`district-votes-for-track-${row.number}`}
                                    pct={maxVotes > 0 ? (row.forCount / maxVotes) * 100 : 0}
                                    colorClassName="bg-vote-for-light dark:bg-vote-for-dark"
                                    count={row.forCount}
                                />
                                <BarLine
                                    testID={`district-votes-against-fill-${row.number}`}
                                    trackTestID={`district-votes-against-track-${row.number}`}
                                    pct={maxVotes > 0 ? (row.againstCount / maxVotes) * 100 : 0}
                                    colorClassName="bg-vote-against-light dark:bg-vote-against-dark"
                                    count={row.againstCount}
                                />
                                <RowRepresentatives row={row} />
                            </View>
                        </View>
                    ))}
                    <Legend
                        testID="district-votes-legend"
                        items={[
                            { label: "For", className: "bg-vote-for-light dark:bg-vote-for-dark" },
                            { label: "Against", className: "bg-vote-against-light dark:bg-vote-against-dark" },
                        ]}
                    />
                </View>
            </View>

            {maxAbsNet > 0 ? (
                <View
                    testID="district-affinity-chart"
                    accessible
                    accessibilityRole="image"
                    accessibilityLabel={netLabel}
                >
                    <View className="gap-2">
                        <SectionLabel>Net votes by district</SectionLabel>
                        {visibleRows.map((row) => {
                            const pct = (Math.abs(row.net) / maxAbsNet) * 50;
                            const positive = row.net >= 0;
                            return (
                                <View
                                    key={row.key}
                                    testID={`district-affinity-row-${row.number}`}
                                    className="flex-row items-center gap-3 rounded-md px-2 py-1"
                                    style={row.isReaderDistrict ? { backgroundColor: highlight } : undefined}
                                >
                                    <RowLabel row={row} />
                                    <View
                                        testID={`district-affinity-track-${row.number}`}
                                        className={`h-3 flex-1 overflow-hidden rounded-full ${TRACK_COLOR}`}
                                    >
                                        <View
                                            testID={`district-affinity-fill-${row.number}`}
                                            className={
                                                positive
                                                    ? "bg-vote-for-light dark:bg-vote-for-dark"
                                                    : "bg-vote-against-light dark:bg-vote-against-dark"
                                            }
                                            style={{
                                                position: "absolute",
                                                top: 0,
                                                height: "100%",
                                                width: `${pct}%`,
                                                left: positive ? "50%" : `${50 - pct}%`,
                                            }}
                                        />
                                        <View
                                            className="bg-border-strong-light dark:bg-border-strong-dark"
                                            style={{ position: "absolute", top: 0, bottom: 0, left: "50%", width: 1 }}
                                        />
                                    </View>
                                    <CountText>{signedNet(row.net)}</CountText>
                                </View>
                            );
                        })}
                        <Legend
                            testID="district-affinity-legend"
                            items={[
                                { label: "Net against", className: "bg-vote-against-light dark:bg-vote-against-dark" },
                                { label: "Net for", className: "bg-vote-for-light dark:bg-vote-for-dark" },
                            ]}
                        />
                    </View>
                </View>
            ) : null}

            {canToggle ? (
                <Pressable
                    testID="district-votes-toggle"
                    variant="ghost"
                    onPress={() => setExpanded((value) => !value)}
                    accessibilityLabel={expanded ? "Show fewer districts" : `Show all ${rows.length} districts`}
                    accessibilityState={{ expanded }}
                >
                    <Text className="text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark">
                        {expanded ? "Show fewer districts" : `Show all ${rows.length} districts`}
                    </Text>
                </Pressable>
            ) : null}
        </View>
    );
}

export default DistrictVotesPanel;
