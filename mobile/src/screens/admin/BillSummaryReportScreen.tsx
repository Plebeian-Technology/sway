// @lat: [[mobile-admin-area#The bill summary report screen]]
import React, { useState } from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";

import { Routes } from "../../api/routes";
import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { FormField } from "../../components/ui/FormField";
import { Pressable } from "../../components/ui/Pressable";
import { useAdminMutation } from "../../hooks/admin/useAdminMutation";
import { useBillSummaryReport, type BillSummaryReport } from "../../hooks/admin/useBillSummaryReport";
import type { BillSummaryReportStatus } from "../../hooks/admin/useBillSummaryReports";
import type { AdminStackParamList } from "../../navigation/types";

type Props = Pick<NativeStackScreenProps<AdminStackParamList, "AdminBillSummaryReport">, "route">;

const STATUS_OPTIONS: { key: BillSummaryReportStatus; label: string }[] = [
    { key: "pending", label: "Pending" },
    { key: "reviewed", label: "Reviewed" },
    { key: "resolved", label: "Resolved" },
    { key: "dismissed", label: "Dismissed" },
];

const LabeledText = ({ label, value }: { label: string; value: string }) => (
    <View>
        <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
            {label}
        </Text>
        <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">{value}</Text>
    </View>
);

const ReviewForm = ({ report, onSaved }: { report: BillSummaryReport; onSaved: () => void }) => {
    const [status, setStatus] = useState<BillSummaryReportStatus>(report.status);
    const [adminNotes, setAdminNotes] = useState(report.admin_notes ?? "");
    const [saved, setSaved] = useState(false);
    const { run, loading, errorMessage } = useAdminMutation("patch", Routes.adminBillSummaryReport(report.id));

    const save = async () => {
        setSaved(false);
        const result = await run({ bill_summary_report: { status, admin_notes: adminNotes } });
        if (result === undefined) return;
        setSaved(true);
        onSaved();
    };

    return (
        <Card className="mx-4 mb-3">
            <Text className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Review
            </Text>
            <View className="flex-row flex-wrap gap-2">
                {STATUS_OPTIONS.map((option) => (
                    <Pressable
                        key={option.key}
                        testID={`admin-bill-summary-report-status-${option.key}`}
                        variant={status === option.key ? "default" : "outline"}
                        disabled={loading}
                        onPress={() => setStatus(option.key)}
                        accessibilityLabel={option.label}
                        accessibilityState={{ selected: status === option.key }}
                    >
                        <Text
                            className={`text-sm font-open-sans-semibold${
                                status === option.key
                                    ? " text-primary-foreground-light dark:text-primary-foreground-dark"
                                    : " text-foreground-light dark:text-foreground-dark"
                            }`}
                        >
                            {option.label}
                        </Text>
                    </Pressable>
                ))}
            </View>
            <FormField
                testID="admin-bill-summary-report-notes"
                label="Admin notes"
                value={adminNotes}
                onChangeText={setAdminNotes}
                disabled={loading}
            />
            {errorMessage ? (
                <Text
                    testID="admin-bill-summary-report-error"
                    className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {errorMessage}
                </Text>
            ) : null}
            {saved ? (
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    Saved.
                </Text>
            ) : null}
            <Pressable
                testID="admin-bill-summary-report-save"
                variant="default"
                disabled={loading}
                onPress={() => void save()}
                accessibilityLabel="Save the report review"
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Saving..." : "Save"}
                </Text>
            </Pressable>
        </Card>
    );
};

export default function BillSummaryReportScreen({ route }: Props) {
    const { data, loading, error, refresh } = useBillSummaryReport(route.params.id);

    return (
        <ScrollView
            testID="admin-bill-summary-report-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            keyboardShouldPersistTaps="handled"
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the report"
                />
            }
        >
            {error ? (
                <EmptyState title={error.message} testID="admin-bill-summary-report-load-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-bill-summary-report-loading" className="py-12" />
            ) : (
                <>
                    <View className="px-4 pt-6 pb-4">
                        <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                            {`Report #${data.id}`}
                        </Text>
                        <Text
                            accessibilityRole="header"
                            className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                        >
                            {`${data.bill_external_id}: ${data.bill_title}`}
                        </Text>
                        {data.sway_locale_name ? (
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                {data.sway_locale_name}
                            </Text>
                        ) : null}
                    </View>
                    <Card className="mx-4 mb-3">
                        <LabeledText label="Reason" value={data.reason_label} />
                        {data.details ? <LabeledText label="Reader feedback" value={data.details} /> : null}
                        <LabeledText label="Reporter" value={`${data.reporter_display} · ${data.created_at}`} />
                        {data.resolved_by_name && data.resolved_at ? (
                            <LabeledText label="Resolved by" value={`${data.resolved_by_name} · ${data.resolved_at}`} />
                        ) : null}
                        {data.summary_snapshot ? (
                            <LabeledText
                                label={
                                    data.summary_ai_unreviewed
                                        ? "Summary the reader saw (AI, unreviewed)"
                                        : "Summary the reader saw"
                                }
                                value={data.summary_snapshot}
                            />
                        ) : null}
                        {data.bill_current_summary ? (
                            <LabeledText label="Current summary" value={data.bill_current_summary} />
                        ) : null}
                    </Card>
                    <ReviewForm
                        report={data}
                        onSaved={() => {
                            void refresh();
                        }}
                    />
                </>
            )}
        </ScrollView>
    );
}
