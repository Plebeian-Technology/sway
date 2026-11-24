// @lat: [[mobile-bill-creator#The bill creator screen]]
import React, { useState } from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";

import { EmptyState } from "../../../components/ui/EmptyState";
import { SegmentedControl } from "../../../components/ui/SegmentedControl";
import {
    BILL_CREATOR_TABS,
    useBillCreator,
    type BillCreatorTab,
    type BillCreatorTabProps,
} from "../../../hooks/admin/useBillCreator";
import type { AdminStackParamList } from "../../../navigation/types";
import CreatorTab from "./tabs/CreatorTab";
import PipelineTab from "./tabs/PipelineTab";
import PositionsTab from "./tabs/PositionsTab";
import ScheduleTab from "./tabs/ScheduleTab";
import SummaryTab from "./tabs/SummaryTab";

type Props = Pick<NativeStackScreenProps<AdminStackParamList, "AdminBillCreator">, "route">;

const TAB_LABELS: Record<BillCreatorTab, string> = {
    creator: "Creator",
    schedule: "Schedule",
    pipeline: "Pipeline",
    summary: "Summary",
    positions: "Positions",
};

const TAB_COMPONENTS: Record<BillCreatorTab, React.ComponentType<BillCreatorTabProps>> = {
    creator: CreatorTab,
    schedule: ScheduleTab,
    pipeline: PipelineTab,
    summary: SummaryTab,
    positions: PositionsTab,
};

export default function BillCreatorScreen({ route }: Props) {
    const { billId } = route.params;
    const [tab, setTab] = useState<BillCreatorTab>("creator");
    const { data, error, refresh } = useBillCreator(billId, tab);
    const [pulling, setPulling] = useState(false);
    const TabComponent = TAB_COMPONENTS[tab];

    const pullToRefresh = async () => {
        setPulling(true);
        await refresh();
        setPulling(false);
    };

    return (
        <ScrollView
            testID="admin-bill-creator-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={pulling}
                    onRefresh={() => {
                        void pullToRefresh();
                    }}
                    accessibilityLabel="Pull to refresh the bill"
                />
            }
        >
            <View className="px-4 pt-6 pb-4 gap-1">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    {billId === null ? "New bill" : (data?.bill?.external_id ?? "Bill Creator")}
                </Text>
                {billId !== null && data?.bill?.title ? (
                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        {data.bill.title}
                    </Text>
                ) : null}
            </View>
            <View className="px-4 pb-4">
                <SegmentedControl
                    testID="admin-bill-creator-tabs"
                    accessibilityLabel="Bill creator tabs"
                    segments={BILL_CREATOR_TABS.map((key) => TAB_LABELS[key])}
                    selectedIndex={BILL_CREATOR_TABS.indexOf(tab)}
                    onChange={(index) => setTab(BILL_CREATOR_TABS[index])}
                />
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-bill-creator-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-bill-creator-loading" className="py-12" />
            ) : (
                <TabComponent billId={billId} data={data} refresh={refresh} />
            )}
        </ScrollView>
    );
}
