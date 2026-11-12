import React, { useCallback, useMemo, useState } from "react";
import { ActivityIndicator, FlatList, RefreshControl, Text, View } from "react-native";
import { DrawerActions, useNavigation } from "@react-navigation/native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import BrandHeader from "../components/BrandHeader";
import { OfflineBanner } from "../components/OfflineBanner";
import { SkeletonCard } from "../components/SkeletonCard";
import { EmptyState } from "../components/ui/EmptyState";
import FeedItemRow from "../components/feed/FeedItemRow";
import { groupFeedItemsByDate } from "../components/feed/dateGrouping";
import type { IFeedBill, IFeedItem } from "../components/feed/types";
import { useFeed } from "../hooks/useFeed";
import { useShareBill } from "../hooks/useShareBill";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";

interface NavLike {
    navigate: (route: string, params?: Record<string, unknown>) => void;
}

interface Props {
    navigation: NavLike;
}

type FeedListRow = { type: "header"; key: string; heading: string } | { type: "item"; key: string; item: IFeedItem };

export default function FeedScreen({ navigation }: Props) {
    const nav = useNavigation();
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    const { items, loading, error, loadingMore, pageError, hasMore, isOnline, isResolved, refresh, loadMore } =
        useFeed();
    const { shareBill } = useShareBill();
    const [pullRefreshing, setPullRefreshing] = useState(false);

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
        const parent = nav.getParent() as NavLike | undefined;
        if (parent) {
            parent.navigate("Legislators");
        } else {
            navigation.navigate("Legislators");
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
                        <Text style={{ fontSize: 13, fontWeight: "700", color: t.foreground }}>{row.heading}</Text>
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
                        ctaLabel="Retry"
                        onCtaPress={() => void refresh()}
                    />
                </View>
            ) : items.length === 0 ? (
                <View style={{ flex: 1, padding: 16, justifyContent: "center" }}>
                    <EmptyState testID="feed-empty" title={PARITY_COPY.feed.emptyState} />
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
                    ListFooterComponent={
                        loadingMore ? (
                            <View style={{ paddingVertical: 20, alignItems: "center", gap: 6 }}>
                                <ActivityIndicator color={t.primary} />
                                <Text style={{ fontSize: 13, color: t.mutedForeground }}>
                                    {PARITY_COPY.feed.loadingMore}
                                </Text>
                            </View>
                        ) : pageError ? (
                            <View style={{ padding: 16, alignItems: "center" }}>
                                <Text style={{ fontSize: 13, color: t.destructive }}>{pageError.message}</Text>
                            </View>
                        ) : null
                    }
                />
            )}
        </View>
    );
}
