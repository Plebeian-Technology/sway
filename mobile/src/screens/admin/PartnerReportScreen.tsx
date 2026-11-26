// @lat: [[mobile-admin-area#The partner report screen]]
import React from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";

import { EmptyState } from "../../components/ui/EmptyState";
import { usePartnerReport } from "../../hooks/admin/usePartnerReport";
import type { AdminStackParamList } from "../../navigation/types";
import { CoveredArticles, HeadlineFigures } from "./PartnerReportSections";

type Props = Pick<NativeStackScreenProps<AdminStackParamList, "AdminPartnerReport">, "route">;

export default function PartnerReportScreen({ route }: Props) {
    const { data, loading, error, refresh } = usePartnerReport(route.params.partnerSlug);

    return (
        <ScrollView
            testID="admin-partner-report-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the partner report"
                />
            }
        >
            {error ? (
                <EmptyState title={error.message} testID="admin-partner-report-load-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-partner-report-loading" className="py-12" />
            ) : (
                <>
                    <View className="px-4 pt-6 pb-4">
                        <Text
                            accessibilityRole="header"
                            className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                        >
                            {data.partner_name}
                        </Text>
                        <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {`Engagement metrics, voter conversion, and article coverage for ${data.partner_name} (${data.partner_slug}).`}
                        </Text>
                    </View>
                    <HeadlineFigures partners={[data]} single />
                    <CoveredArticles partners={[data]} single />
                </>
            )}
        </ScrollView>
    );
}
