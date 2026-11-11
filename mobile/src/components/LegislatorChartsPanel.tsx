// @lat: [[mobile-legislator-components-design#LegislatorChartsPanel]]
import React, { useMemo, useState } from "react";
import { Text, View, type LayoutChangeEvent } from "react-native";
import Svg, { Rect } from "react-native-svg";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

export interface LegislatorScore {
    count_agreed?: number | string | null;
    count_disagreed?: number | string | null;
    count_no_legislator_vote?: number | string | null;
    count_legislator_abstained?: number | string | null;
}

export interface LegislatorChartsPanelProps {
    score: LegislatorScore | null | undefined;
    title?: string;
    testID?: string;
}

const BAR_HEIGHT = 12;
const LABEL_WIDTH = 110;
const VALUE_WIDTH = 40;

type Tone = "for" | "against" | "muted";

interface Row {
    key: string;
    label: string;
    value: number;
    tone: Tone;
}

// @lat: [[mobile-legislator-components-design#LegislatorChartsPanel]]
const DEFAULT_CONTAINER_WIDTH = 300;

export function LegislatorChartsPanel({ score, title, testID }: LegislatorChartsPanelProps) {
    const [containerWidth, setContainerWidth] = useState<number>(DEFAULT_CONTAINER_WIDTH);
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const toneColors = useMemo<Record<Tone, string>>(
        () => ({
            for: t.voteFor,
            against: t.voteAgainst,
            muted: t.chartMuted,
        }),
        [t.voteFor, t.voteAgainst, t.chartMuted],
    );

    const handleLayout = (e: LayoutChangeEvent) => {
        const { width } = e.nativeEvent.layout;
        if (width > 0) {
            setContainerWidth(width);
        }
    };

    const rows: Row[] = [
        { key: "agreed", label: "Agreed", value: Number(score?.count_agreed ?? 0), tone: "for" },
        { key: "disagreed", label: "Disagreed", value: Number(score?.count_disagreed ?? 0), tone: "against" },
        {
            key: "abstained",
            label: "Legislator Abstained",
            value: Number(score?.count_legislator_abstained ?? 0),
            tone: "muted",
        },
        {
            key: "no-vote",
            label: "No Legislator Vote",
            value: Number(score?.count_no_legislator_vote ?? 0),
            tone: "muted",
        },
    ];

    const max = rows.reduce((acc, r) => Math.max(acc, r.value), 0);

    const trackWidth = Math.max(0, containerWidth - LABEL_WIDTH - VALUE_WIDTH - 32);

    return (
        <View testID={testID} style={{ paddingHorizontal: 16, paddingVertical: 12 }} onLayout={handleLayout}>
            {title ? (
                <Text
                    className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                    style={{ textTransform: "uppercase", letterSpacing: 1.8, marginBottom: 8 }}
                >
                    {title}
                </Text>
            ) : null}
            {rows.map((row) => {
                const pct = max > 0 ? (row.value / max) * 100 : 0;
                const barWidth = Math.max(0, (trackWidth * pct) / 100);
                return (
                    <View
                        key={row.key}
                        accessibilityLabel={`${row.label} ${row.value}`}
                        style={{ flexDirection: "row", alignItems: "center", gap: 8, marginBottom: 6 }}
                    >
                        <Text
                            className="text-[11px] font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                            style={{ width: LABEL_WIDTH, textTransform: "uppercase", letterSpacing: 1.4 }}
                            numberOfLines={1}
                        >
                            {row.label}
                        </Text>
                        <View
                            style={{
                                flex: 1,
                                height: BAR_HEIGHT + 4,
                                justifyContent: "center",
                            }}
                        >
                            <Svg width={trackWidth} height={BAR_HEIGHT + 4}>
                                <Rect
                                    x={0}
                                    y={2}
                                    width={barWidth}
                                    height={BAR_HEIGHT}
                                    rx={4}
                                    fill={toneColors[row.tone]}
                                    testID={`${testID ?? "charts-panel"}-bar-${row.key}`}
                                />
                            </Svg>
                        </View>
                        <Text
                            className="text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                            style={{ width: VALUE_WIDTH, textAlign: "right", fontVariant: ["tabular-nums"] }}
                        >
                            {row.value}
                        </Text>
                    </View>
                );
            })}
        </View>
    );
}

export default LegislatorChartsPanel;
