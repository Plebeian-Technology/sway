import React, { useCallback, useMemo, useRef, useState } from "react";
import { Image, Linking, RefreshControl, ScrollView, Text, View } from "react-native";
import { useFocusEffect } from "@react-navigation/native";
import { ChevronRight, ExternalLink, Mail, MapPin, Phone, X, User } from "lucide-react-native";

import { useLegislators } from "../hooks/useLegislators";
import { useLegislator } from "../hooks/useLegislator";
import { useBootstrap } from "../hooks/useBootstrap";
import { useFocusedSync } from "../hooks/useFocusedSync";
import { LegislatorChartsPanel } from "../components/LegislatorChartsPanel";
import { ScoreTilesRow } from "../components/ScoreTilesRow";
import { SkeletonCard } from "../components/SkeletonCard";
import { Pressable } from "../components/ui/Pressable";
import { EmptyState } from "../components/ui/EmptyState";
import { SegmentedControl } from "../components/ui/SegmentedControl";
import { StampedBadge } from "../components/StampedBadge";
import { LegislatorTermCard } from "../components/legislators/LegislatorTermCard";
import { LegislatorBillOfTheMonthRecord } from "../components/legislators/LegislatorBillOfTheMonthRecord";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { isSafeCitationUrl } from "../utils/safeUrl";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { Legislator, ILegislatorTermEntry } from "../types/legislator";

interface RouteLike {
    params: { id: number | string };
}

interface Props {
    route: RouteLike;
    navigation?: {
        navigate: (screen: "BillDetail", params: { id: number }) => void;
    };
}

export default function LegislatorDetailScreen({ route, navigation }: Props) {
    const id = Number(route.params.id);
    const { bootstrap } = useBootstrap();
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const activeLocaleId = (bootstrap?.locale?.id as number | undefined) ?? 0;

    const { data, loading, error, refresh } = useLegislators(
        activeLocaleId ? { swayLocaleId: activeLocaleId } : undefined,
    );
    const { data: detail, loading: detailLoading, error: detailError, refresh: refreshDetail } = useLegislator(id);

    const syncRefresh = useCallback(() => {
        void refresh();
        void refreshDetail();
    }, [refresh, refreshDetail]);

    useFocusedSync({ refresh: syncRefresh, pollMs: 15000 });

    const syncRefreshRef = useRef(syncRefresh);
    syncRefreshRef.current = syncRefresh;
    const hasFocusedRef = useRef(false);
    useFocusEffect(
        useCallback(() => {
            if (!hasFocusedRef.current) {
                hasFocusedRef.current = true;
                return;
            }
            syncRefreshRef.current();
        }, []),
    );

    const [isPullRefreshing, setIsPullRefreshing] = useState(false);
    const handlePullRefresh = useCallback(async () => {
        setIsPullRefreshing(true);
        try {
            await Promise.all([refresh(), refreshDetail()]);
        } finally {
            setIsPullRefreshing(false);
        }
    }, [refresh, refreshDetail]);

    const fetchedDetail = detail?.id === id ? detail : null;
    const legislator = useMemo<Legislator | null>(() => {
        const listed = data.find((leg) => leg.id === id) ?? null;
        if (!listed && !fetchedDetail) return null;
        return { ...listed, ...fetchedDetail } as Legislator;
    }, [data, fetchedDetail, id]);

    const sortedTerms = useMemo(() => {
        const terms = (legislator as Legislator | null)?.terms;
        if (!terms || terms.length === 0) return [];
        return [...terms].sort(
            (a: ILegislatorTermEntry, b: ILegislatorTermEntry) => b.term_start_year - a.term_start_year,
        );
    }, [legislator]);

    const score = legislator?.user_legislator_score ?? null;

    // @lat: [[scores-and-agreement#Scores and agreement#An at-large official has no district tally worth drawing]]
    const isAtLarge = useMemo(() => {
        const n = legislator?.district?.number;
        return n == null || Number(n) === 0;
    }, [legislator]);

    const swayLocaleLabel = useMemo(() => {
        const swayLocale = (bootstrap?.locale ?? {}) as Record<string, unknown>;
        const parts = [swayLocale.city, swayLocale.region_name, swayLocale.country].filter(
            (p): p is string => typeof p === "string" && p.length > 0,
        );
        return parts.length ? parts.join(", ") : "Locale";
    }, [bootstrap]);

    const [tabIndex, setTabIndex] = useState<0 | 1 | 2>(0);

    const isFormerRep = legislator?.active === false;

    const termYearRange = useMemo(() => {
        if (typeof legislator?.term_start_year === "number" && typeof legislator?.term_end_year === "number") {
            return `${legislator.term_start_year}\u2013${legislator.term_end_year}`;
        }
        return null;
    }, [legislator]);

    const tabLabels = useMemo(() => {
        const currentLabel = isFormerRep && termYearRange ? termYearRange : "Current Term";
        return [currentLabel, PARITY_COPY.legislators.tabLifetime, "Term History"];
    }, [isFormerRep, termYearRange]);

    const handleEmailPress = useCallback(() => {
        if (legislator?.email) {
            void Linking.openURL(`mailto:${String(legislator.email)}`);
        }
    }, [legislator]);

    const handlePhonePress = useCallback(() => {
        if (legislator?.phone) {
            void Linking.openURL(`tel:${String(legislator.phone)}`);
        }
    }, [legislator]);

    const handleTwitterPress = useCallback(() => {
        if (legislator?.twitter) {
            const handle = String(legislator.twitter).replace(/^@/, "");
            void Linking.openURL(`https://twitter.com/${handle}`);
        }
    }, [legislator]);

    const safeOfficialLink =
        legislator?.link && isSafeCitationUrl(String(legislator.link)) ? String(legislator.link) : null;

    const handleLinkPress = useCallback(() => {
        if (legislator?.link && isSafeCitationUrl(String(legislator.link))) {
            void Linking.openURL(String(legislator.link)).catch(() => {});
        }
    }, [legislator]);

    const districtLabel = useMemo(() => {
        const d = legislator?.district;
        if (!d) return null;
        const parts = [d.name ?? (d.number != null ? `District ${d.number}` : null), d.region_code ?? null].filter(
            Boolean,
        );
        return parts.length ? parts.join(", ") : null;
    }, [legislator]);

    const handleDistrictPress = useCallback(() => {
        if (!districtLabel) return;
        const q = encodeURIComponent(districtLabel);
        void Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${q}`);
    }, [districtLabel]);

    const [failedPhotoUrl, setFailedPhotoUrl] = useState<string | null>(null);

    if ((loading || detailLoading) && !legislator) {
        return (
            <View className="p-4" testID="legislator-detail-skeleton">
                <SkeletonCard />
            </View>
        );
    }

    if (!legislator) {
        const loadError = error ?? detailError;
        if (loadError) {
            return (
                <View className="flex-1 bg-dominant-light dark:bg-dominant-dark p-4" testID="legislator-detail-error">
                    <EmptyState title={loadError.message || "Couldn't load legislator"} />
                    <Pressable
                        variant="outline"
                        onPress={syncRefresh}
                        testID="legislator-not-found-retry"
                        accessibilityLabel={PARITY_COPY.legislators.historyRetry}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.legislators.historyRetry}
                        </Text>
                    </Pressable>
                </View>
            );
        }
        return (
            <View className="flex-1 bg-dominant-light dark:bg-dominant-dark p-4" testID="legislator-detail-not-found">
                <EmptyState title="Legislator not found" />
            </View>
        );
    }

    return (
        <ScrollView
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ padding: 16 }}
            refreshControl={
                <RefreshControl
                    refreshing={isPullRefreshing}
                    onRefresh={handlePullRefresh}
                    accessibilityLabel="Pull to refresh legislator detail"
                />
            }
        >
            <View
                testID="legislator-detail-header"
                style={{ flexDirection: "row", alignItems: "center", gap: 16, marginBottom: 20 }}
            >
                <View
                    style={{
                        width: 96,
                        height: 112,
                        borderRadius: 6,
                        borderWidth: 1,
                        borderColor: t.avatarBorder,
                        backgroundColor: t.input,
                        alignItems: "center",
                        justifyContent: "center",
                        overflow: "hidden",
                    }}
                >
                    {legislator.photo_url && failedPhotoUrl !== legislator.photo_url ? (
                        <Image
                            source={{ uri: legislator.photo_url }}
                            accessibilityLabel={`${legislator.full_name ?? "Legislator"} avatar`}
                            style={{ width: 96, height: 112 }}
                            resizeMode="cover"
                            onError={() => setFailedPhotoUrl(legislator.photo_url ?? null)}
                        />
                    ) : (
                        <User size={36} color={t.mutedIcon} testID="legislator-detail-avatar-fallback" />
                    )}
                </View>
                <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: "row", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                        <Text
                            className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                            accessibilityRole="header"
                        >
                            {legislator.full_name ?? "Legislator"}
                        </Text>
                        {isFormerRep ? (
                            <StampedBadge
                                label={PARITY_COPY.legislators.endedStamp}
                                color={t.mutedForeground}
                                testID="legislator-detail-ended-stamp"
                            />
                        ) : null}
                    </View>
                    {legislator.title ? (
                        <Text
                            className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                            style={{ textTransform: "uppercase", letterSpacing: 2.5, marginTop: 4 }}
                        >
                            {legislator.title}
                        </Text>
                    ) : null}
                </View>
            </View>

            <View className="mb-4" testID="legislator-detail-tab-container">
                <SegmentedControl
                    testID="legislator-detail-tabs"
                    segments={tabLabels}
                    selectedIndex={tabIndex}
                    onChange={(idx) => setTabIndex(idx as 0 | 1 | 2)}
                    accessibilityLabel="Agreement timeframes"
                />
                {tabIndex !== 2 && termYearRange && !isFormerRep ? (
                    <Text
                        testID="legislator-term-year-range"
                        className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark mt-2"
                    >
                        {termYearRange}
                    </Text>
                ) : null}
            </View>

            {tabIndex === 0 ? (
                <>
                    <ScoreTilesRow
                        score={score}
                        testID="legislator-detail-score-tiles"
                        className="flex-row gap-3 mb-4"
                    />

                    {/* @lat: [[legislators-tab-switching-design#Why Legislators.tsx switches tabs without a server round trip#Mobile: LegislatorDetailScreen's chart list]] */}
                    {score ? (
                        <View testID="legislator-detail-charts" className="gap-3 mb-4">
                            <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                <LegislatorChartsPanel
                                    score={score}
                                    title={`Your agreement with ${legislator.full_name ?? "this legislator"}`}
                                    testID="legislator-detail-chart-user"
                                />
                            </View>
                            {!isAtLarge && score.legislator_district_score ? (
                                <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                    <LegislatorChartsPanel
                                        score={score.legislator_district_score}
                                        title={`District ${legislator.district?.number} agreement with ${legislator.full_name ?? "this legislator"}`}
                                        testID="legislator-detail-chart-district"
                                    />
                                </View>
                            ) : null}
                            {score.legislator_locale_score ? (
                                <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                    <LegislatorChartsPanel
                                        score={score.legislator_locale_score}
                                        title={`${swayLocaleLabel} agreement with ${legislator.full_name ?? "this legislator"}`}
                                        testID="legislator-detail-chart-locale"
                                    />
                                </View>
                            ) : null}
                        </View>
                    ) : null}
                </>
            ) : null}

            {tabIndex === 1 ? (
                <>
                    <ScoreTilesRow
                        score={legislator.lifetime_score ?? null}
                        testID="legislator-detail-score-tiles-lifetime"
                        className="flex-row gap-3 mb-4"
                    />

                    {legislator.lifetime_score ? (
                        <View testID="legislator-detail-charts-lifetime" className="gap-3 mb-4">
                            <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                <LegislatorChartsPanel
                                    score={legislator.lifetime_score}
                                    title={`Your agreement with ${legislator.full_name ?? "this legislator"} · lifetime`}
                                    testID="legislator-detail-chart-user-lifetime"
                                />
                            </View>
                            {!isAtLarge && legislator.lifetime_score.legislator_district_score ? (
                                <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                    <LegislatorChartsPanel
                                        score={legislator.lifetime_score.legislator_district_score}
                                        title={`All districts · lifetime agreement with ${legislator.full_name ?? "this legislator"}`}
                                        testID="legislator-detail-chart-district-lifetime"
                                    />
                                </View>
                            ) : null}
                            {legislator.lifetime_score.legislator_locale_score ? (
                                <View className="bg-surface-3-light dark:bg-surface-3-dark border border-border-light dark:border-border-dark rounded-xl">
                                    <LegislatorChartsPanel
                                        score={legislator.lifetime_score.legislator_locale_score}
                                        title={`${swayLocaleLabel} agreement with ${legislator.full_name ?? "this legislator"} · lifetime`}
                                        testID="legislator-detail-chart-locale-lifetime"
                                    />
                                </View>
                            ) : null}
                        </View>
                    ) : null}
                </>
            ) : null}

            {tabIndex === 2 ? (
                sortedTerms.length === 0 ? (
                    <View className="mb-4">
                        <EmptyState
                            testID="legislator-history-empty"
                            title="No historical terms on record"
                            body="Historical term records and voting score breakdowns are not yet available for this official."
                        />
                    </View>
                ) : (
                    <View testID="legislator-history-terms-list" className="gap-4 mb-4">
                        {sortedTerms.map((term) => (
                            <LegislatorTermCard
                                key={term.id}
                                term={term}
                                legislatorName={legislator.full_name ?? "Legislator"}
                                fallbackDistrictName={districtLabel}
                                isLoggedIn={bootstrap?.current_user != null}
                            />
                        ))}
                    </View>
                )
            ) : null}

            <LegislatorBillOfTheMonthRecord
                votes={fetchedDetail?.bill_of_the_month_votes}
                loading={detailLoading}
                error={detailError}
                isSignedIn={bootstrap?.current_user != null}
                onRetry={() => {
                    void refreshDetail();
                }}
                onSelectBill={(billId) => navigation?.navigate("BillDetail", { id: billId })}
            />

            <ContactRow
                icon={<MapPin size={20} color={t.mutedForeground} />}
                label={districtLabel ?? null}
                hint="Open in Google Maps"
                onPress={handleDistrictPress}
                testID="legislator-detail-district"
            />
            <ContactRow
                icon={<Mail size={20} color={t.mutedForeground} />}
                label={legislator.email ?? null}
                hint="Send email"
                onPress={handleEmailPress}
                testID="legislator-detail-email"
            />
            <ContactRow
                icon={<Phone size={20} color={t.mutedForeground} />}
                label={legislator.phone ?? null}
                hint="Call"
                onPress={handlePhonePress}
                testID="legislator-detail-phone"
            />
            <ContactRow
                icon={<X size={20} color={t.mutedForeground} />}
                label={legislator.twitter ? `@${String(legislator.twitter).replace(/^@/, "")}` : null}
                hint="Open on Twitter"
                onPress={handleTwitterPress}
                testID="legislator-detail-twitter"
            />
            <ContactRow
                icon={<ExternalLink size={20} color={t.mutedForeground} />}
                label={safeOfficialLink ? "Official page" : null}
                hint="Open official website"
                onPress={handleLinkPress}
                testID="legislator-detail-link"
            />
        </ScrollView>
    );
}

interface ContactRowProps {
    icon: React.ReactElement;
    label: string | null;
    hint: string;
    onPress: () => void;
    testID: string;
}

function ContactRow({ icon, label, hint, onPress, testID }: ContactRowProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    if (!label) return null;
    return (
        <Pressable
            variant="ghost"
            onPress={onPress}
            accessibilityRole="link"
            accessibilityLabel={`${hint}: ${label}`}
            accessibilityHint={hint}
            testID={testID}
            className="bg-card-light dark:bg-card-dark border border-border-light dark:border-border-dark rounded-xl mb-2"
            style={{ paddingHorizontal: 14, paddingVertical: 14 }}
        >
            <View style={{ flexDirection: "row", alignItems: "center", gap: 12, width: "100%" }}>
                <View style={{ width: 28, alignItems: "center" }}>{icon}</View>
                <Text
                    style={{ flex: 1 }}
                    className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark"
                    numberOfLines={1}
                >
                    {label}
                </Text>
                <ChevronRight size={18} color={t.borderSoft} />
            </View>
        </Pressable>
    );
}
