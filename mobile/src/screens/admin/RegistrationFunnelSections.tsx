// @lat: [[mobile-admin-area#The registration funnel screen]]
import React from "react";
import { Text, View } from "react-native";

import { Card } from "../../components/ui/Card";
import { Pressable } from "../../components/ui/Pressable";
import { SegmentedControl } from "../../components/ui/SegmentedControl";
import type {
    AttributionBreakdown,
    FrictionPoint,
    FunnelStep,
    LatencyMetrics,
    RegistrationFunnel,
} from "../../hooks/admin/useRegistrationFunnel";
import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { SectionHeading } from "./PartnerReportSections";

const HIGH_STEP_CONVERSION = 70;
const HIGH_FRICTION_RATE = 30;
const MEDIUM_FRICTION_RATE = 15;
const HEALTHY_MEDIAN_SECONDS = 5;

const MUTED = "text-muted-foreground-light dark:text-muted-foreground-dark";
const FOREGROUND = "text-foreground-light dark:text-foreground-dark";

const stepVisitors = (steps: FunnelStep[], ...ids: string[]) =>
    steps.find((step) => ids.includes(step.step))?.visitor_count ?? 0;

export const FilterChip = ({
    label,
    selected,
    onPress,
    testID,
}: {
    label: string;
    selected: boolean;
    onPress: () => void;
    testID?: string;
}) => (
    <Pressable
        testID={testID}
        variant={selected ? "default" : "outline"}
        onPress={onPress}
        accessibilityLabel={label}
        accessibilityState={{ selected }}
    >
        <Text
            className={`text-sm font-open-sans-semibold${
                selected ? " text-primary-foreground-light dark:text-primary-foreground-dark" : ` ${FOREGROUND}`
            }`}
        >
            {label}
        </Text>
    </Pressable>
);

export const Filters = ({
    funnel,
    onTimeRange,
    onTraffic,
    onClearAttribution,
}: {
    funnel: RegistrationFunnel;
    onTimeRange: (id: string) => void;
    onTraffic: (id: RegistrationFunnel["traffic"]) => void;
    onClearAttribution: () => void;
}) => {
    const botLabel = funnel.traffic === "humans" ? "Bot visitors filtered out" : "Bot visitors in range";
    return (
        <View className="px-4 pb-3 gap-3">
            <View className="flex-row flex-wrap gap-2">
                {funnel.time_ranges.map((range) => (
                    <FilterChip
                        key={range.id}
                        testID={`admin-registration-funnel-range-${range.id}`}
                        label={range.label}
                        selected={funnel.time_range === range.id}
                        onPress={() => onTimeRange(range.id)}
                    />
                ))}
            </View>
            <SegmentedControl
                testID="admin-registration-funnel-traffic"
                accessibilityLabel="Traffic"
                segments={funnel.traffic_options.map((option) => option.label)}
                selectedIndex={funnel.traffic_options.findIndex((option) => option.id === funnel.traffic)}
                onChange={(index) => onTraffic(funnel.traffic_options[index].id)}
            />
            <Text className={`text-sm font-open-sans-light ${MUTED}`}>
                {`${botLabel}: ${funnel.bot_visitor_count.toLocaleString()}`}
            </Text>
            {funnel.filter_attribution_key ? (
                <Card className="gap-2">
                    <Text className={`text-sm font-open-sans-semibold ${FOREGROUND}`}>
                        {`Filtered by referral source: ${funnel.filter_attribution_key}`}
                    </Text>
                    <Pressable variant="outline" onPress={onClearAttribution} accessibilityLabel="Clear Filter">
                        <Text className={`text-sm font-open-sans-semibold ${FOREGROUND}`}>Clear Filter</Text>
                    </Pressable>
                </Card>
            ) : null}
        </View>
    );
};

const Figure = ({ label, value, note, testID }: { label: string; value: string; note: string; testID: string }) => (
    <Card className="mx-4 mb-3">
        <Text className={`text-sm font-open-sans-semibold ${MUTED}`}>{label}</Text>
        <Text testID={testID} className={`text-2xl font-open-sans-bold ${FOREGROUND}`}>
            {value}
        </Text>
        <Text className={`text-xs font-open-sans-light ${MUTED}`}>{note}</Text>
    </Card>
);

export const HeadlineFigures = ({ funnel }: { funnel: RegistrationFunnel }) => {
    const landing = stepVisitors(funnel.steps, "landing");
    const registrations = stepVisitors(funnel.steps, "registration_completed", "geocoding_completed");
    return (
        <>
            <Figure
                testID="admin-registration-funnel-landing-visitors"
                label="Landing Visitors"
                value={landing.toLocaleString()}
                note="Initial entry impressions"
            />
            <Figure
                testID="admin-registration-funnel-completed-registrations"
                label="Completed Registrations"
                value={registrations.toLocaleString()}
                note={landing > 0 ? `${((registrations / landing) * 100).toFixed(1)}% of visitors` : "0%"}
            />
            <Figure
                testID="admin-registration-funnel-first-votes"
                label="First Votes Cast"
                value={stepVisitors(funnel.steps, "first_vote_cast").toLocaleString()}
                note="Activated civic participants"
            />
            <Figure
                testID="admin-registration-funnel-overall-conversion"
                label="Overall Funnel Conversion"
                value={`${funnel.overall_conversion_rate}%`}
                note="Landing → First Vote"
            />
        </>
    );
};

const clampPercent = (value: number) => Math.min(100, Math.max(0, value));

const StepRow = ({ step, index }: { step: FunnelStep; index: number }) => {
    const { colorScheme } = useTheme();
    const tokens = swayTokens[colorScheme];
    return (
        <View className="gap-2 mb-4">
            <View className="flex-row items-center gap-2">
                <Text className={`w-6 text-center text-xs font-open-sans-semibold ${MUTED}`}>{index + 1}</Text>
                <Text className={`flex-1 text-sm font-open-sans-semibold ${FOREGROUND}`}>{step.label}</Text>
                <Text className={`text-sm font-open-sans-semibold ${FOREGROUND}`}>
                    {`${step.visitor_count.toLocaleString()} visitors`}
                </Text>
            </View>
            {index > 0 ? (
                <View className="flex-row flex-wrap items-center gap-2">
                    <Text
                        className="text-xs font-open-sans-semibold"
                        style={{
                            color:
                                step.step_conversion_rate >= HIGH_STEP_CONVERSION ? tokens.success : tokens.foreground,
                        }}
                    >
                        {`${step.step_conversion_rate}% step conversion`}
                    </Text>
                    <Text className={`text-xs font-open-sans-light ${MUTED}`}>
                        {`(${step.drop_off_count} dropped / ${step.drop_off_rate}%)`}
                    </Text>
                </View>
            ) : null}
            <View className="h-3 overflow-hidden rounded-full bg-muted-light dark:bg-muted-dark">
                <View
                    testID={`admin-registration-funnel-bar-${step.step}`}
                    className="h-3 rounded-full bg-primary-light dark:bg-primary-dark"
                    style={{ width: `${clampPercent(step.conversion_rate_from_start)}%` }}
                />
            </View>
        </View>
    );
};

export const FunnelSteps = ({ steps }: { steps: FunnelStep[] }) => (
    <>
        <SectionHeading
            title="Step-by-Step Funnel Progression"
            description="Progression of unique visitors through each stage of the registration workflow."
        />
        <View className="px-4">
            {steps.map((step, index) => (
                <StepRow key={step.step} step={step} index={index} />
            ))}
        </View>
    </>
);

const FrictionRow = ({ point, rank }: { point: FrictionPoint; rank: number }) => {
    const { colorScheme } = useTheme();
    const tokens = swayTokens[colorScheme];
    const rateColor =
        point.drop_off_rate >= HIGH_FRICTION_RATE
            ? tokens.destructive
            : point.drop_off_rate >= MEDIUM_FRICTION_RATE
              ? tokens.warning
              : tokens.foreground;
    return (
        <Card testID={`admin-registration-funnel-friction-${rank}`} className="mx-4 mb-3 gap-1">
            <View className="flex-row items-center gap-2">
                <Text
                    className="text-xs font-open-sans-bold"
                    style={{ color: rank === 1 ? tokens.destructive : tokens.mutedForeground }}
                >
                    {`#${rank}`}
                </Text>
                <Text className={`flex-1 text-sm font-open-sans-semibold ${FOREGROUND}`}>{point.label}</Text>
            </View>
            <Text className={`text-xs font-open-sans-light ${MUTED}`}>
                {`${point.drop_off_count.toLocaleString()} users dropped`}
            </Text>
            <Text className="text-xs font-open-sans-semibold" style={{ color: rateColor }}>
                {`${point.drop_off_count} users (${point.drop_off_rate}%)`}
            </Text>
        </Card>
    );
};

export const FrictionPoints = ({
    points,
    rankBy,
    onRankBy,
}: {
    points: FrictionPoint[];
    rankBy: "count" | "rate";
    onRankBy: (rankBy: "count" | "rate") => void;
}) => {
    const ranked = [...points].sort((a, b) =>
        rankBy === "count" ? a.rank_by_count - b.rank_by_count : a.rank_by_rate - b.rank_by_rate,
    );
    return (
        <>
            <SectionHeading
                title="Top Friction Points"
                description="Ranked drop-off bottlenecks between consecutive steps."
            />
            <View className="px-4 pb-3">
                <SegmentedControl
                    testID="admin-registration-funnel-rank-by"
                    accessibilityLabel="Rank friction points by"
                    segments={["Lost Users", "Drop-off %"]}
                    selectedIndex={rankBy === "count" ? 0 : 1}
                    onChange={(index) => onRankBy(index === 0 ? "count" : "rate")}
                />
            </View>
            {ranked.length === 0 ? (
                <Text className={`px-4 py-6 text-center text-sm font-open-sans-light ${MUTED}`}>
                    No drop-off events recorded in this period.
                </Text>
            ) : (
                ranked.map((point, index) => <FrictionRow key={point.label} point={point} rank={index + 1} />)
            )}
        </>
    );
};

const LatencyFigure = ({ label, value, note }: { label: string; value: string; note: string }) => (
    <Card className="mx-4 mb-3">
        <Text className={`text-sm font-open-sans-semibold ${MUTED}`}>{label}</Text>
        <Text className={`text-2xl font-open-sans-bold ${FOREGROUND}`}>{value}</Text>
        <Text className={`text-xs font-open-sans-light ${MUTED}`}>{note}</Text>
    </Card>
);

const LatencyVerdict = ({ latency }: { latency: LatencyMetrics }) => {
    const { colorScheme } = useTheme();
    const tokens = swayTokens[colorScheme];
    if (latency.sample_count === 0) {
        return (
            <Text className={`px-4 pb-3 text-sm font-open-sans-light ${MUTED}`}>
                No completed geocoding operations recorded in this time range.
            </Text>
        );
    }
    const healthy = latency.median_seconds <= HEALTHY_MEDIAN_SECONDS;
    return (
        <Text
            className="px-4 pb-3 text-sm font-open-sans-semibold"
            style={{ color: healthy ? tokens.success : tokens.warning }}
        >
            {healthy ? "Geocoding performance is healthy (<5s median)." : "Elevated geocoding latency detected."}
        </Text>
    );
};

export const GeocodingLatency = ({ latency }: { latency: LatencyMetrics }) => (
    <>
        <SectionHeading
            title="Async Geocoding Latency"
            description="Time spent in pending / processing before legislative assignment completes."
        />
        <LatencyFigure
            label="Median (p50) Latency"
            value={`${latency.median_seconds}s`}
            note="Typical waiting duration"
        />
        <LatencyFigure label="95th Percentile (p95)" value={`${latency.p95_seconds}s`} note="Tail latency threshold" />
        <LatencyFigure
            label="Average Latency"
            value={`${latency.avg_seconds}s`}
            note={`Range: ${latency.min_seconds}s – ${latency.max_seconds}s`}
        />
        <LatencyFigure label="Completed Samples" value={String(latency.sample_count)} note="Measured background jobs" />
        <LatencyVerdict latency={latency} />
    </>
);

const AttributionRow = ({
    attribution,
    onInspect,
}: {
    attribution: AttributionBreakdown;
    onInspect: (source: string) => void;
}) => (
    <Card className="mx-4 mb-3 gap-1">
        <Text className={`font-mono text-sm font-open-sans-semibold ${FOREGROUND}`}>{attribution.source}</Text>
        <Text className={`text-sm font-open-sans-light ${FOREGROUND}`}>
            {`${attribution.visitors_count.toLocaleString()} visitors · ${attribution.registrations_count.toLocaleString()} registrations · ${attribution.votes_count.toLocaleString()} first votes`}
        </Text>
        <Text
            className={`text-xs font-open-sans-semibold ${FOREGROUND}`}
        >{`${attribution.conversion_rate}% conversion`}</Text>
        <Text className={`text-xs font-open-sans-semibold ${FOREGROUND}`}>{`${attribution.vote_rate}% vote rate`}</Text>
        <Pressable
            testID={`admin-registration-funnel-inspect-${attribution.source}`}
            variant="outline"
            onPress={() => onInspect(attribution.source)}
            accessibilityLabel={`Inspect ${attribution.source}`}
        >
            <Text className={`text-sm font-open-sans-semibold ${FOREGROUND}`}>Inspect</Text>
        </Pressable>
    </Card>
);

export const ReferralSources = ({
    attributions,
    onInspect,
}: {
    attributions: AttributionBreakdown[];
    onInspect: (source: string) => void;
}) => (
    <>
        <SectionHeading
            title="Referral Source Attribution"
            description="Traffic and conversion breakdown by invite links (/s/:key) and organic direct entries."
        />
        {attributions.length === 0 ? (
            <Text className={`px-4 py-6 text-center text-sm font-open-sans-light ${MUTED}`}>
                No attribution events recorded in this time range.
            </Text>
        ) : (
            attributions.map((attribution) => (
                <AttributionRow key={attribution.source} attribution={attribution} onInspect={onInspect} />
            ))
        )}
    </>
);
