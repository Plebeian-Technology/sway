// @lat: [[mobile-bill-detail-and-bill-of-the-month-screens#BillDetailScreen and BillOfTheMonthScreen]]
import React, { useCallback, useEffect, useRef, useState } from "react";
import { ScrollView, RefreshControl, View } from "react-native";
import { useNavigation, type NavigationProp, type ParamListBase } from "@react-navigation/native";

import { useBill } from "../hooks/useBill";
import { useFocusedSync } from "../hooks/useFocusedSync";
import { useBootstrap } from "../hooks/useBootstrap";
import { useSession } from "../hooks/useSession";
import { BillScreenTabs, type BillScreenTabsBill, type BillScreenTabsBillScore } from "../components/BillScreenTabs";
import type { OrgPosition } from "../components/OrgPositionsSection";
import { EmptyState } from "../components/ui/EmptyState";
import { SkeletonCard } from "../components/SkeletonCard";
import type { PublicTestimonyCounts } from "../types/bill";
import type { DistrictRef } from "../utils/districtVotes";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

interface RouteLike {
    params: { id: number };
}

interface BillDetailScreenProps {
    route: RouteLike;
}

type BillRecord = BillScreenTabsBill & { sway_locale_id?: number };

interface SponsorRecord {
    full_name?: string;
}

interface UserVoteRecord {
    support?: "for" | "against" | "FOR" | "AGAINST" | null;
}

export default function BillDetailScreen({ route }: BillDetailScreenProps) {
    const { id } = route.params;
    if (!Number.isInteger(id) || id <= 0) {
        return (
            <View testID="bill-detail-error" className="flex-1 bg-dominant-light p-6 dark:bg-dominant-dark">
                <EmptyState title={PARITY_COPY.bill.detailError} testID="bill-detail-empty" />
            </View>
        );
    }
    return <BillDetailLoaded id={id} />;
}

interface BillDetailLoadedProps {
    id: number;
}

function BillDetailLoaded({ id }: BillDetailLoadedProps) {
    const nav = useNavigation();
    const bill = useBill(id);
    const { refresh: refreshBill } = bill;
    const { bootstrap } = useBootstrap();
    const { isAuthenticated } = useSession();

    const refetch = useCallback(() => {
        void refreshBill();
    }, [refreshBill]);

    // @lat: [[bill-page-polling-props-rationale#Mobile: useFocusedSync on BillDetailScreen and BillOfTheMonthScreen]]
    useFocusedSync({ refresh: refetch, pollMs: 15000 });

    const [pullRefreshing, setPullRefreshing] = useState(false);
    useEffect(() => {
        if (!bill.loading) setPullRefreshing(false);
    }, [bill.loading]);
    const handlePullRefresh = useCallback(() => {
        setPullRefreshing(true);
        refetch();
    }, [refetch]);

    const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const handleVoted = useCallback(() => {
        if (timerRef.current) clearTimeout(timerRef.current);
        timerRef.current = setTimeout(() => {
            void refreshBill();
        }, 1500);
    }, [refreshBill]);
    useEffect(
        () => () => {
            if (timerRef.current) clearTimeout(timerRef.current);
        },
        [],
    );

    if (bill.loading && !bill.data) {
        return (
            <View className="p-4" testID="bill-detail-skeleton">
                <SkeletonCard heightClass="h-32" />
            </View>
        );
    }

    if (bill.error && !bill.data) {
        return (
            <ScrollView
                testID="bill-detail-error"
                className="flex-1 bg-dominant-light dark:bg-dominant-dark"
                contentContainerStyle={{ flexGrow: 1, padding: 24 }}
                refreshControl={<RefreshControl refreshing={pullRefreshing} onRefresh={handlePullRefresh} />}
            >
                <EmptyState
                    title={PARITY_COPY.bill.detailError}
                    ctaLabel={PARITY_COPY.legislators.historyRetry}
                    onCtaPress={refetch}
                    testID="bill-detail-empty"
                />
            </ScrollView>
        );
    }

    if (!bill.data) {
        return null;
    }

    const billPayload = (bill.data.bill ?? bill.data) as unknown as BillRecord;
    const sponsor = (bill.data.sponsor ?? null) as SponsorRecord | null;
    const userVote = (bill.data.user_vote ?? null) as UserVoteRecord | null;
    const billScore = (bill.data.bill_score ?? null) as BillScreenTabsBillScore | null;
    const organizations = ((bill.data as Record<string, unknown>).organizations ?? []) as OrgPosition[];
    const publicTestimonyCounts = ((bill.data as Record<string, unknown>).public_testimony_counts ??
        null) as PublicTestimonyCounts | null;
    const sponsorId = billPayload.legislator_id;

    // @lat: [[mobile-bill-detail-and-bill-of-the-month-screens#BillDetailScreen's data source quirks]]
    const swayLocales = bootstrap?.sway_locales;
    const billLocale = billPayload.sway_locale_id
        ? swayLocales?.find((l) => l.id === billPayload.sway_locale_id)
        : null;
    const swayLocaleSlug = billLocale?.name ?? bootstrap?.locale?.name ?? "";
    const genericPortalUrls = billLocale?.generic_portal_urls ?? bootstrap?.locale?.generic_portal_urls;

    // @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]
    const billInActiveLocale =
        billPayload.sway_locale_id != null && billPayload.sway_locale_id === bootstrap?.locale?.id;
    const readerDistricts = billInActiveLocale ? ((bill.data.districts ?? []) as DistrictRef[]) : [];

    return (
        <ScrollView
            testID="bill-detail-scroll"
            contentContainerStyle={{ padding: 16, gap: 16, paddingBottom: 32 }}
            refreshControl={<RefreshControl refreshing={pullRefreshing} onRefresh={handlePullRefresh} />}
        >
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
                detailLoaded
                detailError={bill.error}
                onRetry={refetch}
                onVoted={handleVoted}
                onNavigateToLegislators={() =>
                    nav
                        .getParent<NavigationProp<ParamListBase>>()
                        ?.navigate("Legislators", { screen: "LegislatorsList", pop: true })
                }
                onNavigateToBills={() => nav.getParent()?.navigate("Bills" as never)}
                onSponsorPress={
                    sponsorId != null
                        ? () =>
                              nav
                                  .getParent<NavigationProp<ParamListBase>>()
                                  ?.navigate("Legislators", { screen: "LegislatorDetail", params: { id: sponsorId } })
                        : undefined
                }
                heroTestID="bill-detail-hero"
                summariesTestID="bill-detail-summaries"
            />
        </ScrollView>
    );
}
