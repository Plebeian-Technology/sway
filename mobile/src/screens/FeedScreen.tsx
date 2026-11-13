import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ActivityIndicator, FlatList, RefreshControl, Text, TextInput, View } from "react-native";
import { DrawerActions, useFocusEffect, useNavigation } from "@react-navigation/native";
import { Search, X } from "lucide-react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import BrandHeader from "../components/BrandHeader";
import { OfflineBanner } from "../components/OfflineBanner";
import { SkeletonCard } from "../components/SkeletonCard";
import { EmptyState } from "../components/ui/EmptyState";
import { Pressable } from "../components/ui/Pressable";
import FeedItemRow from "../components/feed/FeedItemRow";
import { groupFeedItemsByDate } from "../components/feed/dateGrouping";
import type { IFeedBill, IFeedItem } from "../components/feed/types";
import { useFeed } from "../hooks/useFeed";
import { useShareBill } from "../hooks/useShareBill";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

interface INavLike {
    navigate: (route: string, params?: Record<string, unknown>) => void;
}

interface IProps {
    navigation: INavLike;
}

type FeedListRow = { type: "header"; key: string; heading: string } | { type: "item"; key: string; item: IFeedItem };

const SEARCH_DEBOUNCE_MS = 300;

const FeedScreen: React.FC<IProps> = ({ navigation }) => {
    const nav = useNavigation();
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const [searchText, setSearchText] = useState("");
    const [debouncedSearch, setDebouncedSearch] = useState("");

    useEffect(() => {
        if (searchText === debouncedSearch) {
            return;
        }
        const timer = setTimeout(() => {
            setDebouncedSearch(searchText);
        }, SEARCH_DEBOUNCE_MS);
        return () => clearTimeout(timer);
    }, [debouncedSearch, searchText]);

    const {
        items,
        matchCount,
        loading,
        error,
        loadingMore,
        pageError,
        hasMore,
        isOnline,
        isResolved,
        refresh,
        loadMore,
    } = useFeed(debouncedSearch);
    const { shareBill } = useShareBill();
    const [pullRefreshing, setPullRefreshing] = useState(false);

    const refreshRef = useRef(refresh);
    refreshRef.current = refresh;
    const hasFocusedRef = useRef(false);
    useFocusEffect(
        useCallback(() => {
            if (!hasFocusedRef.current) {
                hasFocusedRef.current = true;
                return;
            }
            void refreshRef.current();
        }, []),
    );

    const activeQuery = debouncedSearch.trim();
    const isSearching = activeQuery.length > 0;

    const handleClearSearch = useCallback(() => {
        setSearchText("");
        setDebouncedSearch("");
    }, []);

    const handlePullRefresh = useCallback(async () => {
        setPullRefreshing(true);
        try {
            await refresh();
        } finally {
            setPullRefreshing(false);
        }
    }, [refresh]);

    const handlePressBill = useCallback(
        (billId: number) => {
            navigation.navigate("BillDetail", { id: billId });
        },
        [navigation],
    );

    const handleShareBill = useCallback(
        (bill: IFeedBill) => {
            void shareBill({ id: bill.id, title: bill.title });
        },
        [shareBill],
    );

    const handlePressLegislators = useCallback(() => {
        const targetParams = { screen: "LegislatorsList", pop: true };
        const parent = nav.getParent() as INavLike | undefined;
        if (parent) {
            parent.navigate("Legislators", targetParams);
        } else {
            navigation.navigate("Legislators", targetParams);
        }
    }, [nav, navigation]);

    const handlePressBills = useCallback(() => {
        const targetParams = { screen: "BillsList", pop: true };
        const parent = nav.getParent() as INavLike | undefined;
        if (parent) {
            parent.navigate("Bills", targetParams);
        } else {
            navigation.navigate("Bills", targetParams);
        }
    }, [nav, navigation]);

    const handleEndReached = useCallback(() => {
        if (hasMore && !loadingMore) {
            void loadMore();
        }
    }, [hasMore, loadMore, loadingMore]);

    const rows = useMemo<FeedListRow[]>(() => {
        const groups = groupFeedItemsByDate(items);
        const flattened: FeedListRow[] = [];
        groups.forEach((group, groupIndex) => {
            flattened.push({
                type: "header",
                key: `header-${group.heading}-${groupIndex}`,
                heading: group.heading,
            });
            for (const item of group.items) {
                flattened.push({
                    type: "item",
                    key: item.key,
                    item,
                });
            }
        });
        return flattened;
    }, [items]);

    const renderRow = useCallback(
        ({ item: row }: { item: FeedListRow }) => {
            if (row.type === "header") {
                return (
                    <View
                        style={{
                            borderBottomWidth: 1,
                            borderBottomColor: t.border,
                            backgroundColor: t.background,
                            paddingHorizontal: 16,
                            paddingTop: 20,
                            paddingBottom: 8,
                        }}
                    >
                        <Text
                            style={{
                                fontFamily: "OpenSans-SemiBold",
                                fontSize: 13,
                                color: t.foreground,
                            }}
                        >
                            {row.heading}
                        </Text>
                    </View>
                );
            }

            return (
                <FeedItemRow
                    item={row.item}
                    onPressBill={handlePressBill}
                    onShareBill={handleShareBill}
                    onPressLegislators={handlePressLegislators}
                />
            );
        },
        [handlePressBill, handlePressLegislators, handleShareBill, t.background, t.border, t.foreground],
    );

    return (
        <View testID="feed-screen" style={{ flex: 1, backgroundColor: t.background }}>
            <BrandHeader title={PARITY_COPY.feed.title} onMenuPress={() => nav.dispatch(DrawerActions.openDrawer())} />
            {isResolved && !isOnline ? <OfflineBanner /> : null}

            <View
                style={{
                    borderBottomWidth: 1,
                    borderBottomColor: t.border,
                    backgroundColor: t.card,
                    paddingHorizontal: 16,
                    paddingVertical: 12,
                }}
            >
                <View
                    style={{
                        flexDirection: "row",
                        alignItems: "center",
                        gap: 8,
                        minHeight: 44,
                        borderRadius: 8,
                        borderWidth: 1,
                        borderColor: t.border,
                        backgroundColor: t.input,
                        paddingLeft: 12,
                        paddingRight: 4,
                    }}
                >
                    <Search size={18} color={t.mutedForeground} />
                    <TextInput
                        testID="feed-search-input"
                        value={searchText}
                        onChangeText={setSearchText}
                        placeholder={PARITY_COPY.feed.searchPlaceholder}
                        placeholderTextColor={t.mutedForeground}
                        accessibilityLabel={PARITY_COPY.feed.searchLabel}
                        autoCapitalize="none"
                        autoCorrect={false}
                        returnKeyType="search"
                        style={{
                            flex: 1,
                            fontFamily: "OpenSans-Regular",
                            fontSize: 14,
                            color: t.foreground,
                            paddingVertical: 8,
                        }}
                    />
                    {searchText.length > 0 ? (
                        <Pressable
                            variant="ghost"
                            onPress={handleClearSearch}
                            testID="feed-search-clear"
                            accessibilityLabel={PARITY_COPY.feed.clearSearch}
                            className="w-11 h-11 !px-0 !py-0"
                        >
                            <X size={18} color={t.mutedForeground} />
                        </Pressable>
                    ) : null}
                </View>
            </View>

            {loading && items.length === 0 ? (
                <View style={{ padding: 16, gap: 12 }} testID="feed-loading">
                    <SkeletonCard />
                    <SkeletonCard />
                    <SkeletonCard />
                </View>
            ) : error && items.length === 0 ? (
                <View style={{ flex: 1, padding: 16, justifyContent: "center" }}>
                    <EmptyState
                        testID="feed-error"
                        title={PARITY_COPY.feed.searchError}
                        body={error.message}
                        ctaLabel={PARITY_COPY.feed.retry}
                        onCtaPress={() => void refresh()}
                    />
                </View>
            ) : isResolved && !isOnline && items.length === 0 ? (
                <View style={{ flex: 1, padding: 16, justifyContent: "center" }}>
                    <EmptyState
                        testID="feed-offline"
                        title={PARITY_COPY.feed.searchError}
                        body={PARITY_COPY.feed.offlineBody}
                        ctaLabel={PARITY_COPY.feed.retry}
                        onCtaPress={() => void refresh()}
                    />
                </View>
            ) : items.length === 0 ? (
                <View style={{ flex: 1, padding: 16, justifyContent: "center" }}>
                    {isSearching ? (
                        <View testID="feed-search-empty" style={{ alignItems: "center", gap: 8, paddingVertical: 24 }}>
                            <Text
                                style={{
                                    fontFamily: "OpenSans-Regular",
                                    fontSize: 14,
                                    color: t.mutedForeground,
                                    textAlign: "center",
                                }}
                            >
                                {PARITY_COPY.feed.searchNoMatches(activeQuery)}
                            </Text>
                            <View
                                style={{
                                    flexDirection: "row",
                                    flexWrap: "wrap",
                                    alignItems: "center",
                                    justifyContent: "center",
                                }}
                            >
                                <Text
                                    style={{
                                        fontFamily: "OpenSans-Regular",
                                        fontSize: 14,
                                        color: t.mutedForeground,
                                        textAlign: "center",
                                    }}
                                >
                                    {PARITY_COPY.feed.searchBrowsePrefix}
                                </Text>
                                <Pressable
                                    variant="ghost"
                                    accessibilityRole="link"
                                    accessibilityLabel={PARITY_COPY.feed.searchBrowseLink}
                                    onPress={handlePressBills}
                                    className="!px-2 !py-0"
                                    style={{ minWidth: 44 }}
                                >
                                    <Text
                                        style={{
                                            fontFamily: "OpenSans-SemiBold",
                                            fontSize: 14,
                                            color: t.primary,
                                            textDecorationLine: "underline",
                                        }}
                                    >
                                        {PARITY_COPY.feed.searchBrowseLink}
                                    </Text>
                                </Pressable>
                            </View>
                        </View>
                    ) : (
                        <EmptyState testID="feed-empty" title={PARITY_COPY.feed.emptyState} />
                    )}
                </View>
            ) : (
                <FlatList
                    testID="feed-list"
                    data={rows}
                    keyExtractor={(row) => row.key}
                    renderItem={renderRow}
                    initialNumToRender={20}
                    onEndReached={handleEndReached}
                    onEndReachedThreshold={0.4}
                    refreshControl={<RefreshControl refreshing={pullRefreshing} onRefresh={handlePullRefresh} />}
                    ListHeaderComponent={
                        error || isSearching ? (
                            <View>
                                {error ? (
                                    <View
                                        testID="feed-refresh-error"
                                        style={{
                                            flexDirection: "row",
                                            alignItems: "center",
                                            justifyContent: "space-between",
                                            gap: 12,
                                            borderBottomWidth: 1,
                                            borderBottomColor: t.border,
                                            backgroundColor: t.card,
                                            paddingHorizontal: 16,
                                            paddingVertical: 10,
                                        }}
                                    >
                                        <Text
                                            style={{
                                                flex: 1,
                                                fontFamily: "OpenSans-Regular",
                                                fontSize: 13,
                                                color: t.destructive,
                                            }}
                                        >
                                            {error.message}
                                        </Text>
                                        <Pressable
                                            variant="outline"
                                            onPress={() => void refresh()}
                                            accessibilityLabel={PARITY_COPY.feed.retry}
                                            className="!rounded-md !px-3.5"
                                            style={{ minWidth: 44 }}
                                        >
                                            <Text
                                                style={{
                                                    fontFamily: "OpenSans-SemiBold",
                                                    fontSize: 13,
                                                    color: t.accent,
                                                }}
                                            >
                                                {PARITY_COPY.feed.retry}
                                            </Text>
                                        </Pressable>
                                    </View>
                                ) : null}
                                {isSearching ? (
                                    <View
                                        style={{
                                            borderBottomWidth: 1,
                                            borderBottomColor: t.border,
                                            paddingHorizontal: 16,
                                            paddingVertical: 12,
                                        }}
                                    >
                                        <Text
                                            style={{
                                                fontFamily: "OpenSans-Regular",
                                                fontSize: 13,
                                                color: t.mutedForeground,
                                            }}
                                        >
                                            {PARITY_COPY.feed.searchMatchCount(matchCount, activeQuery)}
                                        </Text>
                                    </View>
                                ) : null}
                            </View>
                        ) : null
                    }
                    ListFooterComponent={
                        loadingMore ? (
                            <View style={{ paddingVertical: 20, alignItems: "center", gap: 6 }}>
                                <ActivityIndicator color={t.primary} />
                                <Text
                                    style={{
                                        fontFamily: "OpenSans-Regular",
                                        fontSize: 13,
                                        color: t.mutedForeground,
                                    }}
                                >
                                    {PARITY_COPY.feed.loadingMore}
                                </Text>
                            </View>
                        ) : pageError ? (
                            <View style={{ padding: 16, alignItems: "center" }}>
                                <Text
                                    style={{
                                        fontFamily: "OpenSans-Regular",
                                        fontSize: 13,
                                        color: t.destructive,
                                    }}
                                >
                                    {pageError.message}
                                </Text>
                            </View>
                        ) : isSearching ? (
                            <View
                                style={{
                                    paddingHorizontal: 16,
                                    paddingVertical: 20,
                                    flexDirection: "row",
                                    flexWrap: "wrap",
                                    alignItems: "center",
                                    justifyContent: "center",
                                }}
                            >
                                <Text
                                    style={{
                                        fontFamily: "OpenSans-Regular",
                                        fontSize: 13,
                                        color: t.mutedForeground,
                                        textAlign: "center",
                                    }}
                                >
                                    {PARITY_COPY.feed.searchBrowsePrefix}
                                </Text>
                                <Pressable
                                    variant="ghost"
                                    accessibilityRole="link"
                                    accessibilityLabel={PARITY_COPY.feed.searchBrowseLink}
                                    onPress={handlePressBills}
                                    className="!px-2 !py-0"
                                    style={{ minWidth: 44 }}
                                >
                                    <Text
                                        style={{
                                            fontFamily: "OpenSans-SemiBold",
                                            fontSize: 13,
                                            color: t.primary,
                                            textDecorationLine: "underline",
                                        }}
                                    >
                                        {PARITY_COPY.feed.searchBrowseLink}
                                    </Text>
                                </Pressable>
                            </View>
                        ) : null
                    }
                />
            )}
        </View>
    );
};

export default FeedScreen;
