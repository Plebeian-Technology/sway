// @lat: [[mobile-legislators-list-screen#LegislatorsListScreen]]
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { FlatList, RefreshControl, ScrollView, Text, View } from "react-native";
import { DrawerActions, useNavigation } from "@react-navigation/native";

import BrandHeader from "../components/BrandHeader";
import { useLegislators, type LegislatorHistoryEntry, type LegislatorRecord } from "../hooks/useLegislators";
import { useBootstrap } from "../hooks/useBootstrap";
import { useFocusedSync } from "../hooks/useFocusedSync";
import { LegislatorCard } from "../components/LegislatorCard";
import { FadeInItem } from "../components/ui/FadeInItem";
import { SkeletonCard } from "../components/SkeletonCard";
import { OfflineBanner } from "../components/OfflineBanner";
import { EmptyState } from "../components/ui/EmptyState";
import { SwayLocalePickerSheet } from "../components/SwayLocalePickerSheet";
import { Pressable } from "../components/ui/Pressable";
import { SegmentedControl } from "../components/ui/SegmentedControl";
import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { toFormattedLocaleName } from "../utils/locale";

const computeRosterSignature = (reps: LegislatorRecord[]) =>
    reps
        .map((l) =>
            [
                l.id,
                l.active ?? "",
                (l.ended_on as string | undefined) ?? "",
                l.term_start_year ?? "",
                l.term_end_year ?? "",
            ].join(":"),
        )
        .sort()
        .join(",");

// @lat: [[mobile-legislators-list-screen#History]]
type TTabIndex = 0 | 1 | 2;

type HistoryRow =
    | { type: "header"; key: string; label: string }
    | { type: "entry"; key: string; entry: LegislatorHistoryEntry };

interface NavLike {
    navigate: (route: string, params?: Record<string, unknown>) => void;
}

interface Props {
    navigation: NavLike;
}

export default function LegislatorsListScreen({ navigation }: Props) {
    const nav = useNavigation();
    const { bootstrap } = useBootstrap();

    const initialLocaleId = (bootstrap?.locale?.id as number | undefined) ?? 0;
    const [activeLocaleId, setActiveLocaleId] = useState(initialLocaleId);

    const { data, waitingForNewTerm, loading, refresh, isOnline, history, historyLoading, historyError, fetchHistory } =
        useLegislators(activeLocaleId ? { swayLocaleId: activeLocaleId } : undefined);

    const legislators = useMemo(() => data ?? [], [data]);

    const swayLocales = bootstrap?.sway_locales;
    const activeLocale = swayLocales?.find((l) => l.id === activeLocaleId) ?? bootstrap?.locale ?? undefined;
    const formattedSwayLocaleName = activeLocale?.name
        ? toFormattedLocaleName(activeLocale.name, false)
        : "your locale";

    useFocusedSync({ refresh, pollMs: 15000 });

    const [tabIndex, setTabIndex] = useState<TTabIndex>(0);
    // @lat: [[legislators-history-per-locale-state#Mobile: LegislatorsListScreen's historyRequestedFor]]
    const [historyRequestedFor, setHistoryRequestedFor] = useState<number | null>(null);
    const historyRequested = historyRequestedFor === activeLocaleId;

    const rosterSignature = useMemo(() => computeRosterSignature(legislators), [legislators]);
    const signatureByLocaleRef = useRef<Record<number, string>>(
        activeLocaleId && !loading ? { [activeLocaleId]: rosterSignature } : {},
    );
    const prevRenderRef = useRef<{ localeId: number; legislators: LegislatorRecord[] }>({
        localeId: activeLocaleId,
        legislators,
    });
    const prevInitialLocaleIdRef = useRef(initialLocaleId);
    const syncingInitialLocaleRef = useRef(false);

    useEffect(() => {
        if (prevInitialLocaleIdRef.current === initialLocaleId) return;
        prevInitialLocaleIdRef.current = initialLocaleId;
        if (initialLocaleId !== activeLocaleId) {
            syncingInitialLocaleRef.current = true;
            setActiveLocaleId(initialLocaleId);
            if (tabIndex === 2 && initialLocaleId !== 0) {
                delete signatureByLocaleRef.current[initialLocaleId];
                setHistoryRequestedFor(initialLocaleId);
                void fetchHistory(initialLocaleId);
            } else if (historyRequestedFor !== initialLocaleId) {
                delete signatureByLocaleRef.current[initialLocaleId];
            }
        }
    }, [initialLocaleId, activeLocaleId, tabIndex, historyRequestedFor, fetchHistory]);

    const handleTabChange = useCallback(
        (index: number) => {
            const next = index as TTabIndex;
            setTabIndex(next);
            if (next === 2 && !historyRequested) {
                if (loading || prevRenderRef.current.localeId !== activeLocaleId) {
                    delete signatureByLocaleRef.current[activeLocaleId];
                } else if (activeLocaleId !== 0) {
                    signatureByLocaleRef.current[activeLocaleId] = rosterSignature;
                }
                setHistoryRequestedFor(activeLocaleId);
                void fetchHistory();
            }
        },
        [historyRequested, loading, activeLocaleId, rosterSignature, fetchHistory],
    );

    const handleLocaleChange = useCallback(
        (id: number) => {
            if (id === activeLocaleId) return;
            setActiveLocaleId(id);
            if (tabIndex === 2) {
                delete signatureByLocaleRef.current[id];
                setHistoryRequestedFor(id);
                void fetchHistory(id);
            } else if (historyRequestedFor !== id) {
                delete signatureByLocaleRef.current[id];
            }
        },
        [activeLocaleId, tabIndex, historyRequestedFor, fetchHistory],
    );

    // @lat: [[legislators-history-per-locale-state#Mobile: LegislatorsListScreen's historyRequestedFor]]
    useEffect(() => {
        if (syncingInitialLocaleRef.current) {
            syncingInitialLocaleRef.current = false;
            return;
        }
        if (loading) return;
        const prevRender = prevRenderRef.current;
        if (prevRender.localeId !== activeLocaleId && legislators === prevRender.legislators) {
            return;
        }
        prevRenderRef.current = { localeId: activeLocaleId, legislators };
        if (activeLocaleId !== 0) {
            const prevSig = signatureByLocaleRef.current[activeLocaleId];
            signatureByLocaleRef.current[activeLocaleId] = rosterSignature;
            if (prevSig !== undefined && prevSig !== rosterSignature && historyRequestedFor === activeLocaleId) {
                if (tabIndex === 2) {
                    void fetchHistory();
                } else {
                    setHistoryRequestedFor(null);
                }
            }
        }
    }, [
        initialLocaleId,
        activeLocaleId,
        loading,
        legislators,
        rosterSignature,
        historyRequestedFor,
        tabIndex,
        fetchHistory,
    ]);

    // @lat: [[legislators-tab-switching-design#Mobile: LegislatorsListScreen's term year range]]
    const firstRep = legislators[0];
    const termYearRange =
        typeof firstRep?.term_start_year === "number" && typeof firstRep?.term_end_year === "number"
            ? `${firstRep.term_start_year}–${firstRep.term_end_year}`
            : null;
    const isFirstRepFormer = firstRep?.active === false;
    const tabLabels = useMemo(
        () => [
            isFirstRepFormer && termYearRange ? termYearRange : PARITY_COPY.legislators.tabCurrentTerm,
            PARITY_COPY.legislators.tabLifetime,
            PARITY_COPY.legislators.tabHistory,
        ],
        [isFirstRepFormer, termYearRange],
    );

    const activeMode: "current" | "lifetime" = tabIndex === 1 ? "lifetime" : "current";

    // @lat: [[mobile-legislators-list-screen#"Search again"]]
    const handleSearchAgain = useCallback(async () => {
        await apiClient.post(Routes.userLegislators(), { sway_locale_id: activeLocaleId });
        void refresh();
    }, [activeLocaleId, refresh]);

    const keyExtractor = useCallback((item: LegislatorRecord) => String(item.id), []);

    const renderItem = useCallback(
        ({ item, index }: { item: LegislatorRecord; index: number }) => (
            <FadeInItem index={index}>
                <View className="px-4">
                    <LegislatorCard
                        legislator={item}
                        mode={activeMode}
                        onPress={() => navigation.navigate("LegislatorDetail", { id: item.id })}
                    />
                </View>
            </FadeInItem>
        ),
        [navigation, activeMode],
    );

    const historyRows = useMemo<HistoryRow[]>(() => {
        const sessions = history?.sessions ?? [];
        const rows: HistoryRow[] = [];
        sessions.forEach((session) => {
            rows.push({ type: "header", key: `header-${session.session_label}`, label: session.session_label });
            session.entries.forEach((entry) => {
                rows.push({
                    type: "entry",
                    key: `entry-${session.session_label}-${entry.legislator.id}`,
                    entry,
                });
            });
        });
        return rows;
    }, [history]);

    const historyKeyExtractor = useCallback((row: HistoryRow) => row.key, []);

    const renderHistoryRow = useCallback(
        ({ item }: { item: HistoryRow }) =>
            item.type === "header" ? (
                <Text
                    testID={`legislators-history-header-${item.label}`}
                    className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark px-4 mt-4 mb-2"
                    style={{ textTransform: "uppercase", letterSpacing: 1.6 }}
                >
                    {item.label}
                </Text>
            ) : (
                <View className="px-4">
                    <LegislatorCard
                        legislator={item.entry.legislator}
                        testID={`legislator-history-card-${item.entry.legislator.id}`}
                        historyEntry={{
                            score: item.entry.score,
                            termWindow: `${item.entry.term.term_start_year}–${item.entry.term.term_end_year}`,
                        }}
                    />
                </View>
            ),
        [],
    );

    const openDrawer = () => nav.dispatch(DrawerActions.openDrawer());

    if (loading && legislators.length === 0) {
        return (
            <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="legislators-list-loading">
                {!isOnline ? <OfflineBanner /> : null}
                <BrandHeader
                    title={PARITY_COPY.legislators.title}
                    testID="legislators-brand-header"
                    onMenuPress={openDrawer}
                />
                <View className="p-4">
                    <SkeletonCard />
                    <View className="h-3" />
                    <SkeletonCard />
                    <View className="h-3" />
                    <SkeletonCard />
                </View>
            </View>
        );
    }

    const localePicker = (
        <View className="pt-3">
            <SwayLocalePickerSheet
                locales={swayLocales ?? []}
                currentLocale={activeLocale ?? null}
                onSelect={handleLocaleChange}
                testID="locale-picker-trigger"
            />
        </View>
    );

    // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
    const listHeader = (
        <View testID="legislators-list-controls">
            {localePicker}
            <View className="px-4 pt-3 pb-3">
                <SegmentedControl
                    testID="legislators-tabs"
                    segments={tabLabels}
                    selectedIndex={tabIndex}
                    onChange={handleTabChange}
                />
                {tabIndex !== 2 && termYearRange && !isFirstRepFormer ? (
                    <Text
                        testID="legislators-term-year-range"
                        className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark mt-2"
                    >
                        {termYearRange}
                    </Text>
                ) : null}
            </View>
        </View>
    );

    const renderBody = () => {
        if (legislators.length === 0) {
            return (
                <ScrollView testID="legislators-empty-scroll" contentContainerStyle={{ paddingBottom: 24 }}>
                    {localePicker}
                    {/* @lat: [[mobile-legislators-list-screen#"Search again"]] */}
                    <View testID="legislators-empty-state" className="items-center py-12 gap-4 px-4">
                        <EmptyState
                            title={
                                waitingForNewTerm
                                    ? PARITY_COPY.legislators.waitingForNewTerm(formattedSwayLocaleName)
                                    : PARITY_COPY.legislators.noneFound(formattedSwayLocaleName)
                            }
                        />
                        {!waitingForNewTerm && (
                            <Pressable
                                variant="default"
                                onPress={() => {
                                    void handleSearchAgain();
                                }}
                                testID="btn-search-again"
                                accessibilityLabel={PARITY_COPY.legislators.searchAgain}
                            >
                                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                    {PARITY_COPY.legislators.searchAgain}
                                </Text>
                            </Pressable>
                        )}
                    </View>
                </ScrollView>
            );
        }

        if (tabIndex === 2) {
            if (historyLoading && !history) {
                return (
                    <ScrollView contentContainerStyle={{ paddingBottom: 24 }}>
                        {listHeader}
                        <View testID="legislators-history-loading" className="items-center py-12">
                            <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                                {PARITY_COPY.legislators.loading}
                            </Text>
                        </View>
                    </ScrollView>
                );
            }
            if (historyError && !history) {
                return (
                    <ScrollView contentContainerStyle={{ paddingBottom: 24 }}>
                        {listHeader}
                        <EmptyState
                            testID="legislators-history-error"
                            title={PARITY_COPY.legislators.historyLoadError}
                            ctaLabel={PARITY_COPY.legislators.historyRetry}
                            onCtaPress={() => {
                                void fetchHistory();
                            }}
                        />
                    </ScrollView>
                );
            }
            if (history && history.sessions.length === 0) {
                return (
                    <ScrollView contentContainerStyle={{ paddingBottom: 24 }}>
                        {listHeader}
                        <EmptyState
                            testID="legislators-history-empty"
                            title={PARITY_COPY.legislators.historyEmptyHeading}
                            body={PARITY_COPY.legislators.historyEmptyBody}
                        />
                    </ScrollView>
                );
            }
            return (
                <FlatList
                    testID="legislators-history-list"
                    data={historyRows}
                    keyExtractor={historyKeyExtractor}
                    renderItem={renderHistoryRow}
                    ListHeaderComponent={listHeader}
                    contentContainerStyle={{ paddingBottom: 24 }}
                />
            );
        }

        return (
            <FlatList
                testID="legislators-list"
                data={legislators}
                keyExtractor={keyExtractor}
                renderItem={renderItem}
                ListHeaderComponent={listHeader}
                contentContainerStyle={{ paddingBottom: 24 }}
                refreshControl={
                    <RefreshControl
                        refreshing={loading}
                        onRefresh={() => {
                            void refresh();
                        }}
                        accessibilityLabel="Pull to refresh legislators list"
                    />
                }
            />
        );
    };

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark">
            {!isOnline ? <OfflineBanner /> : null}

            <BrandHeader
                title={PARITY_COPY.legislators.title}
                testID="legislators-brand-header"
                onMenuPress={openDrawer}
            />

            {renderBody()}
        </View>
    );
}
