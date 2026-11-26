// @lat: [[mobile-admin-area#The registration funnel screen]]
import React, { useEffect, useState } from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { EmptyState } from "../../components/ui/EmptyState";
import { useRegistrationFunnel, type FunnelTraffic } from "../../hooks/admin/useRegistrationFunnel";
import type { AdminStackParamList } from "../../navigation/types";
import {
    Filters,
    FrictionPoints,
    FunnelSteps,
    GeocodingLatency,
    HeadlineFigures,
    ReferralSources,
} from "./RegistrationFunnelSections";

export default function RegistrationFunnelScreen() {
    const [timeRange, setTimeRange] = useState<string>("30d");
    const [traffic, setTraffic] = useState<FunnelTraffic>("humans");
    const [attributionKey, setAttributionKey] = useState<string | null>(null);
    const [rankBy, setRankBy] = useState<"count" | "rate">("count");
    const { data, loading, error, refresh } = useRegistrationFunnel(timeRange, traffic, attributionKey);
    const navigation = useNavigation<NativeStackNavigationProp<AdminStackParamList>>();

    useEffect(
        () =>
            navigation.addListener("focus", () => {
                void refresh();
            }),
        [navigation, refresh],
    );

    return (
        <ScrollView
            testID="admin-registration-funnel-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the registration funnel"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Registration Funnel
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Self-hosted telemetry tracking step-by-step conversion, drop-off friction, and async geocoding
                    latency.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-registration-funnel-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-registration-funnel-loading" className="py-12" />
            ) : (
                <>
                    <Filters
                        funnel={data}
                        onTimeRange={setTimeRange}
                        onTraffic={setTraffic}
                        onClearAttribution={() => setAttributionKey(null)}
                    />
                    <HeadlineFigures funnel={data} />
                    <FunnelSteps steps={data.steps} />
                    <FrictionPoints points={data.friction_points} rankBy={rankBy} onRankBy={setRankBy} />
                    <GeocodingLatency latency={data.latency} />
                    <ReferralSources attributions={data.attributions} onInspect={setAttributionKey} />
                </>
            )}
        </ScrollView>
    );
}
