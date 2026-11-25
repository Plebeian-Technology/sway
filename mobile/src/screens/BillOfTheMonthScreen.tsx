// @lat: [[user-vote-submission#Mobile bill screen refresh]]
import React, { useCallback, useEffect, useRef, useState } from "react";
import { ScrollView, RefreshControl, View } from "react-native";
import { DrawerActions, useNavigation, type NavigationProp, type ParamListBase } from "@react-navigation/native";

import { useBill } from "../hooks/useBill";
import { useBootstrap } from "../hooks/useBootstrap";
import { useCastUserVote } from "../hooks/useCastUserVote";
import { useFocusedSync } from "../hooks/useFocusedSync";
import { useSession } from "../hooks/useSession";
import BrandHeader from "../components/BrandHeader";
import { BillScreenTabs, type BillScreenTabsBill, type BillScreenTabsBillScore } from "../components/BillScreenTabs";
import type { OrgPosition } from "../components/OrgPositionsSection";
import { SwayLocalePickerSheet } from "../components/SwayLocalePickerSheet";
import { EmptyState } from "../components/ui/EmptyState";
import { SkeletonCard } from "../components/SkeletonCard";
import { OfflineBanner } from "../components/OfflineBanner";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { PublicTestimonyCounts } from "../types/bill";
import type { DistrictRef } from "../utils/districtVotes";
import { Locale } from "../utils/locale";

interface NavLike {
    navigate: (route: string, params?: Record<string, unknown>) => void;
}

interface Props {
    navigation: NavLike;
}

type UserVoteRecord = { support?: "for" | "against" | "FOR" | "AGAINST" | null } | null;

interface BodyProps {
    botm: Record<string, unknown>;
    bootstrapLoading: boolean;
    refreshBootstrap: (swayLocaleId?: number) => void | Promise<unknown>;
    swayLocales: Locale[];
    currentLocale: Locale | null;
    swayLocaleSlug: string;
    genericPortalUrls?: string[];
    onLocaleSelect: (id: number) => void;
}

const BillOfTheMonthBody: React.FC<BodyProps> = ({
    botm,
    bootstrapLoading,
    refreshBootstrap,
    swayLocales,
    currentLocale,
    swayLocaleSlug,
    genericPortalUrls,
    onLocaleSelect,
}) => {
    const nav = useNavigation();
    // @lat: [[mobile-bill-detail-and-bill-of-the-month-screens#BillOfTheMonthScreen's data source quirks]]
    const bill = useBill(botm.id as number);
    const { refresh: refreshBill } = bill;
    const { isAuthenticated } = useSession();

    const refetchDetail = useCallback(() => {
        void refreshBill();
    }, [refreshBill]);

    // @lat: [[bill-page-polling-props-rationale#Mobile: useFocusedSync on BillDetailScreen and BillOfTheMonthScreen]]
    useFocusedSync({ refresh: refetchDetail, pollMs: 15000 });

    const [pullRefreshing, setPullRefreshing] = useState(false);
    useEffect(() => {
        if (!bootstrapLoading && !bill.loading) setPullRefreshing(false);
    }, [bootstrapLoading, bill.loading]);
    const handlePullRefresh = useCallback(() => {
        setPullRefreshing(true);
        void refreshBootstrap();
        refetchDetail();
    }, [refreshBootstrap, refetchDetail]);

    const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const handleVoted = useCallback(() => {
        if (timerRef.current) clearTimeout(timerRef.current);
        timerRef.current = setTimeout(() => {
            void refreshBootstrap();
            refetchDetail();
        }, 1500);
    }, [refreshBootstrap, refetchDetail]);
    useEffect(
        () => () => {
            if (timerRef.current) clearTimeout(timerRef.current);
        },
        [],
    );

    const detail = bill.data as Record<string, unknown> | null;
    const billPayload = {
        ...botm,
        ...((detail?.bill ?? {}) as Record<string, unknown>),
    } as unknown as BillScreenTabsBill;
    const sponsor = (detail?.sponsor ?? null) as { full_name?: string } | null;
    const userVote = (detail ? (detail.user_vote ?? null) : (botm.user_vote ?? null)) as UserVoteRecord;
    const billScore = (detail?.bill_score ?? null) as BillScreenTabsBillScore | null;
    const organizations = (detail?.organizations ?? []) as OrgPosition[];
    const readerDistricts = (detail?.districts ?? []) as DistrictRef[];
    const publicTestimonyCounts = (detail?.public_testimony_counts ?? null) as PublicTestimonyCounts | null;
    const sponsorId = billPayload.legislator_id;

    return (
        <ScrollView
            testID="botm-scroll"
            contentContainerStyle={{ padding: 16, gap: 16, paddingBottom: 32 }}
            refreshControl={<RefreshControl refreshing={pullRefreshing} onRefresh={handlePullRefresh} />}
        >
            {/* @lat: [[locale-name-is-derived#Mobile SwayLocalePickerSheet edge margin toggle]] */}
            <SwayLocalePickerSheet
                locales={swayLocales}
                currentLocale={currentLocale as Locale}
                onSelect={onLocaleSelect}
                withHoriztonalMargin={false}
            />
            {/* @lat: [[user-vote-submission#Mobile bill screen refresh]] */}
            <BillScreenTabs
                bill={billPayload}
                sponsor={sponsor}
                userVote={userVote}
                billScore={billScore}
                organizations={organizations}
                readerDistricts={readerDistricts}
                swayLocaleSlug={swayLocaleSlug}
                genericPortalUrls={genericPortalUrls}
                publicTestimonyCounts={publicTestimonyCounts}
                isSignedIn={isAuthenticated}
                detailLoaded={detail !== null}
                detailError={bill.error}
                onRetry={refetchDetail}
                onVoted={handleVoted}
                onNavigateToLegislators={() => nav.getParent()?.navigate("Legislators" as never)}
                onNavigateToBills={() => nav.getParent()?.navigate("Bills" as never)}
                onNavigateToSignIn={() => nav.navigate("Auth" as never)}
                onSponsorPress={
                    sponsorId != null
                        ? () =>
                              nav
                                  .getParent<NavigationProp<ParamListBase>>()
                                  ?.navigate("Legislators", { screen: "LegislatorDetail", params: { id: sponsorId } })
                        : undefined
                }
                hero
                heroTestID="botm-hero"
                summariesTestID="botm-summaries"
            />
        </ScrollView>
    );
};

export default function BillOfTheMonthScreen({ navigation: _navigation }: Props) {
    const nav = useNavigation();
    // @lat: [[mobile-bill-detail-and-bill-of-the-month-screens#BillOfTheMonthScreen's data source quirks]]
    const { bootstrap, loading, refetch: refreshBootstrap } = useBootstrap();
    const { isOnline, isResolved } = useCastUserVote();

    const bootstrapExt = bootstrap as unknown as Record<string, unknown> | null;
    const botm = (bootstrapExt?.bill_of_the_month as Record<string, unknown> | null) ?? null;
    const swayLocales = (bootstrapExt?.sway_locales as { id: number; name: string }[] | undefined) ?? [];
    // @lat: [[locale-name-is-derived#Client-side bootstrap locale type narrowing]]
    const currentLocale = (bootstrapExt?.locale as { id: number; name: string } | null) ?? null;
    const swayLocaleSlug = currentLocale?.name ?? "";

    const refetch = useCallback(() => {
        void refreshBootstrap();
    }, [refreshBootstrap]);

    // @lat: [[bill-page-polling-props-rationale#Mobile: useFocusedSync on BillDetailScreen and BillOfTheMonthScreen]]
    useFocusedSync({ refresh: refetch, pollMs: 15000 });

    // @lat: [[sway-locale-id-param-cookie-guard#Mobile: BillOfTheMonthScreen's locale picker]]
    const handleLocaleSelect = useCallback(
        (id: number) => {
            void refreshBootstrap(id);
        },
        [refreshBootstrap],
    );

    const openDrawer = () => nav.dispatch(DrawerActions.openDrawer());

    if (loading && !botm) {
        return (
            <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="botm-loading">
                {!isOnline && isResolved ? <OfflineBanner /> : null}
                <BrandHeader
                    title={PARITY_COPY.billOfTheMonth.title}
                    testID="botm-brand-header"
                    onMenuPress={openDrawer}
                />
                <View className="p-4">
                    <SkeletonCard />
                    <View className="h-3" />
                    <SkeletonCard />
                </View>
            </View>
        );
    }

    if (!botm || !botm.title) {
        return (
            <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="botm-empty-container">
                {!isOnline && isResolved ? <OfflineBanner /> : null}
                <BrandHeader
                    title={PARITY_COPY.billOfTheMonth.title}
                    testID="botm-brand-header"
                    onMenuPress={openDrawer}
                />
                <View className="pt-3">
                    <SwayLocalePickerSheet
                        locales={swayLocales as Locale[]}
                        currentLocale={currentLocale as Locale}
                        onSelect={handleLocaleSelect}
                    />
                </View>
                <EmptyState title={PARITY_COPY.billOfTheMonth.empty} testID="botm-empty" />
            </View>
        );
    }

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="botm-screen">
            {!isOnline && isResolved ? <OfflineBanner /> : null}
            <BrandHeader title={PARITY_COPY.billOfTheMonth.title} testID="botm-brand-header" onMenuPress={openDrawer} />
            <BillOfTheMonthBody
                key={botm.id as number}
                botm={botm}
                bootstrapLoading={loading}
                refreshBootstrap={refreshBootstrap}
                swayLocales={swayLocales as Locale[]}
                currentLocale={currentLocale as Locale | null}
                swayLocaleSlug={swayLocaleSlug}
                genericPortalUrls={bootstrap?.locale?.generic_portal_urls}
                onLocaleSelect={handleLocaleSelect}
            />
        </View>
    );
}
