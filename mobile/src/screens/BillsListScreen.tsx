// @lat: [[mobile-bills-list-screen#BillsListScreen]]
import React, { useCallback, useMemo, useRef, useState } from "react";
import { ActivityIndicator, FlatList, RefreshControl, Text, TextInput, View } from "react-native";
import { DrawerActions, useNavigation } from "@react-navigation/native";

import BrandHeader from "../components/BrandHeader";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { useBillCategories, useBills, type BillRecord, type BillsListMode } from "../hooks/useBills";
import { useBootstrap } from "../hooks/useBootstrap";
import { BillCard, type BillCardBill } from "../components/BillCard";
import { BillsSessionPickerSheet } from "../components/BillsSessionPickerSheet";
import { BillsSortStrip } from "../components/BillsSortStrip";
import { SkeletonCard } from "../components/SkeletonCard";
import { OfflineBanner } from "../components/OfflineBanner";
import { EmptyState } from "../components/ui/EmptyState";
import { FadeInItem } from "../components/ui/FadeInItem";
import { CategoryChipStrip } from "../components/CategoryChipStrip";
import { SwayLocalePickerSheet } from "../components/SwayLocalePickerSheet";
import { Pressable } from "../components/ui/Pressable";
import { SegmentedControl } from "../components/ui/SegmentedControl";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { deriveVisibleBills, DEFAULT_BILLS_SORT, type BillsSortValue } from "../utils/billsList";
import { toFormattedLocaleName } from "../utils/locale";

const MODE_SEGMENTS = [PARITY_COPY.bills.pastBillsOfTheMonthTitle, PARITY_COPY.bills.allBillsTitle];

interface NavLike {
    navigate: (route: string, params?: Record<string, unknown>) => void;
}

interface RouteLike {
    name?: string;
    params?: {
        mode?: BillsListMode;
    };
}

interface Props {
    navigation: NavLike;
    route?: RouteLike;
}

function resolveRouteMode(route?: RouteLike): BillsListMode | undefined {
    if (route?.params?.mode === "past_bills_of_the_month" || route?.params?.mode === "all_bills") {
        return route.params.mode;
    }
    if (route?.name === "PastBillsOfTheMonth") {
        return "past_bills_of_the_month";
    }
    if (route?.name === "BillsList") {
        return "all_bills";
    }
    return undefined;
}

export default function BillsListScreen({ navigation, route }: Props) {
    const nav = useNavigation();
    const { colorScheme } = useTheme();
    const { bootstrap } = useBootstrap();
    const listRef = useRef<FlatList<BillRecord>>(null);

    const routeMode = resolveRouteMode(route);
    const [listMode, setListMode] = useState<BillsListMode>(routeMode ?? "all_bills");
    const [selectedSessionId, setSelectedSessionId] = useState<number | null>(null);
    const [prevRouteMode, setPrevRouteMode] = useState<BillsListMode | undefined>(routeMode);
    const [prevRouteParams, setPrevRouteParams] = useState(route?.params);
    if (routeMode !== prevRouteMode || route?.params !== prevRouteParams) {
        setPrevRouteMode(routeMode);
        setPrevRouteParams(route?.params);
        if (routeMode) {
            setListMode(routeMode);
            if (routeMode === "past_bills_of_the_month") {
                setSelectedSessionId(null);
            }
        }
    }

    const initialLocaleId = (bootstrap?.locale?.id as number | undefined) ?? 0;
    const [activeLocaleId, setActiveLocaleId] = useState(initialLocaleId);
    // @lat: [[mobile-bills-list-screen#Why the active-locale state re-derives during render instead of in a useEffect]]
    const [prevInitialLocaleId, setPrevInitialLocaleId] = useState(initialLocaleId);
    if (initialLocaleId !== prevInitialLocaleId) {
        setPrevInitialLocaleId(initialLocaleId);
        setActiveLocaleId(initialLocaleId);
        setSelectedSessionId(null);
    }

    const {
        data,
        loading,
        refresh,
        isOnline,
        isResolved,
        allCategories: billsCategories,
        legislativeSessions = [],
        selectedLegislativeSessionId = null,
        loadingMore,
        pageError,
        hasMore,
        loadMore,
    } = useBills(activeLocaleId, {
        listMode,
        legislativeSessionId: selectedSessionId,
    });

    const [hasLoadedOnce, setHasLoadedOnce] = useState(false);
    if (!loading && data !== null && !hasLoadedOnce) {
        setHasLoadedOnce(true);
    }

    const { allCategories: hookCategories } = useBillCategories(activeLocaleId);
    const allCategories = billsCategories && billsCategories.length > 0 ? billsCategories : hookCategories;

    const [categories, setCategories] = useState<string[]>([]);

    // @lat: [[bills-category-filter#Bills category filter#What the phone shows instead]]
    const [search, setSearch] = useState("");
    const [sort, setSort] = useState<BillsSortValue>(DEFAULT_BILLS_SORT);

    const filteredBills = useMemo(
        () => deriveVisibleBills(data ?? [], { categories, search, sort }),
        [data, categories, search, sort],
    );

    const swayLocales = bootstrap?.sway_locales;
    const activeLocale = swayLocales?.find((l) => l.id === activeLocaleId) ?? bootstrap?.locale ?? undefined;

    const formattedSwayLocaleName = activeLocale?.name
        ? toFormattedLocaleName(activeLocale.name, false)
        : "your locale";

    const handleToggleCategory = useCallback((cat: string) => {
        setCategories((prev) => (prev.includes(cat) ? prev.filter((c) => c !== cat) : [...prev, cat]));
    }, []);

    const handleClearCategories = useCallback(() => setCategories([]), []);

    const keyExtractor = useCallback((item: BillRecord) => String(item.id), []);

    const renderItem = useCallback(
        ({ item, index }: { item: BillRecord; index: number }) => (
            <FadeInItem index={index}>
                <View className="px-4">
                    <BillCard
                        bill={item as unknown as BillCardBill}
                        onPress={() => navigation.navigate("BillDetail", { id: item.id })}
                    />
                </View>
            </FadeInItem>
        ),
        [navigation],
    );

    const renderFooter = useCallback(() => {
        if (loadingMore) {
            return (
                <View className="py-4 items-center" testID="bills-list-loading-more">
                    <ActivityIndicator accessibilityLabel="Loading more bills..." />
                </View>
            );
        }
        if (pageError) {
            return (
                <View className="py-4 px-4 items-center gap-2" testID="bills-list-page-error">
                    <Text className="text-sm text-center text-muted-foreground-light dark:text-muted-foreground-dark font-open-sans-light">
                        Could not load more bills.
                    </Text>
                    <Pressable
                        onPress={() => {
                            void loadMore();
                        }}
                        variant="outline"
                        accessibilityLabel="Retry loading more"
                        accessibilityRole="button"
                        testID="bills-retry-load-more"
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Retry loading more
                        </Text>
                    </Pressable>
                </View>
            );
        }
        if (filteredBills.length === 0 && hasMore) {
            return (
                <View className="py-4 px-4 items-center gap-2" testID="bills-search-expand-prompt">
                    <Text className="text-sm text-center text-muted-foreground-light dark:text-muted-foreground-dark font-open-sans-light">
                        Search found no matches in loaded bills. Check remaining bills on server.
                    </Text>
                    <Pressable
                        onPress={() => {
                            void loadMore();
                        }}
                        variant="outline"
                        accessibilityLabel="Check remaining bills on server"
                        accessibilityRole="button"
                        testID="bills-load-next-page"
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Load more from server
                        </Text>
                    </Pressable>
                </View>
            );
        }
        if (!hasMore && filteredBills.length > 0) {
            return (
                <View className="py-6 items-center" testID="bills-list-end-divider">
                    <View className="w-16 h-0.5 bg-border-light dark:bg-border-dark rounded-full" />
                </View>
            );
        }
        return null;
    }, [loadingMore, pageError, filteredBills.length, hasMore, loadMore]);

    const headerTitle =
        listMode === "past_bills_of_the_month"
            ? PARITY_COPY.bills.pastBillsOfTheMonthTitle
            : PARITY_COPY.bills.allBillsTitle;
    const openDrawer = () => nav.dispatch(DrawerActions.openDrawer());

    if (!hasLoadedOnce && loading && (!data || data.length === 0)) {
        return (
            <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="bills-list-loading">
                {!isOnline && isResolved ? <OfflineBanner /> : null}
                <BrandHeader title={headerTitle} testID="bills-brand-header" onMenuPress={openDrawer} />
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

    const showSessionPicker = listMode !== "past_bills_of_the_month" && legislativeSessions.length > 0;

    // @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]]
    const listHeader = (
        <View testID="bills-list-controls">
            <View className="px-4 pt-3 pb-3">
                <SegmentedControl
                    testID="bills-mode-tabs"
                    segments={MODE_SEGMENTS}
                    selectedIndex={listMode === "past_bills_of_the_month" ? 0 : 1}
                    onChange={(idx) => {
                        const nextMode: BillsListMode = idx === 0 ? "past_bills_of_the_month" : "all_bills";
                        setListMode(nextMode);
                        if (nextMode === "past_bills_of_the_month") {
                            setSelectedSessionId(null);
                        }
                    }}
                    accessibilityLabel="Bills view mode"
                />
            </View>

            <SwayLocalePickerSheet
                locales={swayLocales ?? []}
                currentLocale={activeLocale ?? null}
                onSelect={(id) => {
                    setActiveLocaleId(id);
                    setSelectedSessionId(null);
                }}
                testID="locale-picker-trigger"
            />

            {showSessionPicker ? (
                <BillsSessionPickerSheet
                    sessions={legislativeSessions}
                    selectedSessionId={selectedSessionId ?? selectedLegislativeSessionId}
                    onSelect={(id) => {
                        const activeSession = legislativeSessions.find((session) => session.active);
                        setSelectedSessionId(activeSession?.id === id ? null : id);
                    }}
                    testID="bills-session-picker-trigger"
                />
            ) : null}

            {/* @lat: [[mobile-bills-list-screen#BillsListScreen]] */}
            <View className="px-4 pt-3">
                <TextInput
                    value={search}
                    onChangeText={setSearch}
                    placeholder={PARITY_COPY.bills.searchPlaceholder}
                    placeholderTextColor={swayTokens[colorScheme].mutedForeground}
                    accessibilityLabel={PARITY_COPY.bills.searchLabel}
                    autoCapitalize="none"
                    autoCorrect={false}
                    returnKeyType="search"
                    clearButtonMode="while-editing"
                    className="border border-border-strong-light dark:border-border-strong-dark rounded-xl px-4 py-3 bg-card-light dark:bg-card-dark font-open-sans text-foreground-light dark:text-foreground-dark"
                    style={{ minHeight: 44 }}
                    testID="bills-search-input"
                />
            </View>

            <BillsSortStrip value={sort} onChange={setSort} testID="bills-sort-strip" />

            <Text className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark px-4 pt-1 pb-1">
                {PARITY_COPY.bills.categoriesLabel.toUpperCase()}
            </Text>
            <CategoryChipStrip
                categories={allCategories}
                selected={categories}
                onToggle={handleToggleCategory}
                onClear={handleClearCategories}
                testID="category-chip-strip"
            />

            {filteredBills.length > 0 && (
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark px-4 pb-2">
                    {PARITY_COPY.bills.showingCount(filteredBills.length, formattedSwayLocaleName)}
                </Text>
            )}
        </View>
    );

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark">
            {!isOnline && isResolved ? <OfflineBanner /> : null}

            {/* @lat: [[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]] */}
            <BrandHeader
                title={headerTitle}
                testID="bills-brand-header"
                onMenuPress={openDrawer}
                titleAction={{
                    onPress: () => listRef.current?.scrollToOffset({ offset: 0, animated: true }),
                    accessibilityLabel: `${headerTitle}, scroll to top`,
                }}
            />

            <FlatList
                ref={listRef}
                testID="bills-list"
                data={filteredBills}
                keyExtractor={keyExtractor}
                renderItem={renderItem}
                ListHeaderComponent={listHeader}
                contentContainerStyle={{ paddingBottom: 24 }}
                keyboardShouldPersistTaps="handled"
                keyboardDismissMode="on-drag"
                refreshControl={
                    <RefreshControl
                        refreshing={loading}
                        onRefresh={() => {
                            void refresh();
                        }}
                        accessibilityLabel="Pull to refresh bills list"
                    />
                }
                ListEmptyComponent={
                    loading ? (
                        <View testID="bills-list-loading" className="px-4">
                            <SkeletonCard />
                            <View className="h-3" />
                            <SkeletonCard />
                            <View className="h-3" />
                            <SkeletonCard />
                        </View>
                    ) : (
                        <EmptyState
                            title={PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
                            testID="bills-empty-state"
                        />
                    )
                }
                ListFooterComponent={renderFooter}
                onEndReached={() => {
                    if (hasMore && !loadingMore && !loading) {
                        void loadMore();
                    }
                }}
                onEndReachedThreshold={0.5}
            />
        </View>
    );
}
