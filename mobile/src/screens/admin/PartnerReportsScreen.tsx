// @lat: [[mobile-admin-area#The partner reports screen]]
import React, { useEffect } from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { EmptyState } from "../../components/ui/EmptyState";
import { usePartnerReports } from "../../hooks/admin/usePartnerReports";
import type { AdminStackParamList } from "../../navigation/types";
import { CoveredArticles, HeadlineFigures, PartnerCard, SectionHeading } from "./PartnerReportSections";

export default function PartnerReportsScreen() {
    const { data, loading, error, refresh } = usePartnerReports();
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
            testID="admin-partner-reports-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the partner reports"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Partner Reports
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Track newsroom partner article engagement, voter reach, and civic conversion.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-partner-reports-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-partner-reports-loading" className="py-12" />
            ) : (
                <>
                    <HeadlineFigures partners={data} single={false} />
                    <SectionHeading
                        title="Partner Newsrooms"
                        description="Aggregated metrics and privacy-preserving sentiment for participating publishers."
                    />
                    {data.length === 0 ? (
                        <Text className="px-4 py-6 text-center text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            No partner newsroom data recorded yet.
                        </Text>
                    ) : (
                        data.map((partner) => (
                            <PartnerCard
                                key={partner.partner_slug}
                                partner={partner}
                                onPress={() =>
                                    navigation.navigate("AdminPartnerReport", { partnerSlug: partner.partner_slug })
                                }
                            />
                        ))
                    )}
                    <CoveredArticles partners={data} single={false} />
                </>
            )}
        </ScrollView>
    );
}
