// @lat: [[mobile-admin-area#The bill summary reports screen]]
import React, { useEffect, useState } from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { Pressable } from "../../components/ui/Pressable";
import {
    useBillSummaryReports,
    type BillSummaryReportRow,
    type BillSummaryReportStatusCounts,
} from "../../hooks/admin/useBillSummaryReports";
import type { AdminStackParamList } from "../../navigation/types";

const STATUS_TABS: { key: keyof BillSummaryReportStatusCounts; label: string }[] = [
    { key: "all", label: "All" },
    { key: "pending", label: "Pending" },
    { key: "reviewed", label: "Reviewed" },
    { key: "resolved", label: "Resolved" },
    { key: "dismissed", label: "Dismissed" },
];

const STATUS_LABELS: Record<BillSummaryReportRow["status"], string> = {
    pending: "Pending",
    reviewed: "Reviewed",
    resolved: "Resolved",
    dismissed: "Dismissed",
};

const FilterChip = ({
    label,
    selected,
    onPress,
    testID,
}: {
    label: string;
    selected: boolean;
    onPress: () => void;
    testID: string;
}) => (
    <Pressable
        testID={testID}
        variant={selected ? "default" : "outline"}
        onPress={onPress}
        accessibilityLabel={label}
        accessibilityState={{ selected }}
    >
        <Text
            className={`text-sm font-open-sans-semibold${
                selected
                    ? " text-primary-foreground-light dark:text-primary-foreground-dark"
                    : " text-foreground-light dark:text-foreground-dark"
            }`}
        >
            {label}
        </Text>
    </Pressable>
);

const ReportCard = ({ report, onPress }: { report: BillSummaryReportRow; onPress: () => void }) => (
    <Card testID={`admin-bill-summary-report-${report.id}`} className="mx-4 mb-3" onPress={onPress}>
        <View className="flex-row items-center justify-between gap-2">
            <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                {`#${report.id}`}
            </Text>
            <Text className="text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {STATUS_LABELS[report.status]}
            </Text>
        </View>
        <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
            {`${report.bill_external_id}: ${report.bill_title}`}
        </Text>
        {report.sway_locale_name ? (
            <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {report.sway_locale_name}
            </Text>
        ) : null}
        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
            {report.reason_label}
        </Text>
        {report.details ? (
            <Text
                numberOfLines={3}
                className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
            >
                {report.details}
            </Text>
        ) : null}
        <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {`${report.reporter_display} · ${report.created_at}`}
        </Text>
    </Card>
);

export default function BillSummaryReportsScreen() {
    const [status, setStatus] = useState<string>("all");
    const [localeId, setLocaleId] = useState<number | null>(null);
    const { data, loading, error, refresh } = useBillSummaryReports(status, localeId);
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
            testID="admin-bill-summary-reports-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the reports"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Bill Summary Reports
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Reports readers filed about inaccurate bill summaries.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-bill-summary-reports-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-bill-summary-reports-loading" className="py-12" />
            ) : (
                <>
                    <View className="flex-row flex-wrap gap-2 px-4 pb-3">
                        {STATUS_TABS.map((tab) => (
                            <FilterChip
                                key={tab.key}
                                testID={`admin-bill-summary-reports-status-${tab.key}`}
                                label={`${tab.label} (${data.status_counts[tab.key]})`}
                                selected={status === tab.key}
                                onPress={() => setStatus(tab.key)}
                            />
                        ))}
                    </View>
                    <View className="flex-row flex-wrap gap-2 px-4 pb-4">
                        <FilterChip
                            testID="admin-bill-summary-reports-locale-all"
                            label="All locales"
                            selected={localeId === null}
                            onPress={() => setLocaleId(null)}
                        />
                        {data.locales.map((locale) => (
                            <FilterChip
                                key={locale.id}
                                testID={`admin-bill-summary-reports-locale-${locale.id}`}
                                label={locale.name}
                                selected={localeId === locale.id}
                                onPress={() => setLocaleId(locale.id)}
                            />
                        ))}
                    </View>
                    {data.reports.length === 0 ? (
                        <EmptyState title="No reports match the current filters." />
                    ) : (
                        data.reports.map((report) => (
                            <ReportCard
                                key={report.id}
                                report={report}
                                onPress={() => navigation.navigate("AdminBillSummaryReport", { id: report.id })}
                            />
                        ))
                    )}
                </>
            )}
        </ScrollView>
    );
}
