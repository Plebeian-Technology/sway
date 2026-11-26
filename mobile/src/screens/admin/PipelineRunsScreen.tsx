// @lat: [[mobile-admin-area#The pipeline runs screen]]
import React from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { usePipelineRuns, type PipelineRunRow } from "../../hooks/admin/usePipelineRuns";

const NO_VALUE = "—";

const STATUS_TONE_CLASSES: Record<string, string> = {
    info: "text-info-light dark:text-info-dark",
    success: "text-success-light dark:text-success-dark",
    warning: "text-warning-foreground-light dark:text-warning-foreground-dark",
    danger: "text-destructive-light dark:text-destructive-dark",
    neutral: "text-muted-foreground-light dark:text-muted-foreground-dark",
};

const STATUS_TONES: Record<string, keyof typeof STATUS_TONE_CLASSES> = {
    queued: "info",
    running: "info",
    fetching_bills: "info",
    fetching_law: "info",
    extracting_text: "info",
    parsing_sections: "info",
    generating_diffs: "info",
    fetching_hearings: "info",
    summarizing: "info",
    succeeded: "success",
    completed: "success",
    partial: "warning",
    cancelled: "warning",
    failed: "danger",
};

const relativeTime = (iso: string) => {
    const seconds = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (seconds < 0) return "just now";
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
};

const formatTime = (iso: string | null) => (iso ? `${relativeTime(iso)} (${iso})` : NO_VALUE);

const Detail = ({ label, value }: { label: string; value: string }) => (
    <View>
        <Text className="text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark">{label}</Text>
        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {value}
        </Text>
    </View>
);

const RunCard = ({ run }: { run: PipelineRunRow }) => (
    <Card testID={`admin-pipeline-run-${run.id}`} className="mx-4 mb-3">
        <View className="flex-row flex-wrap items-center gap-2">
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {`Run #${run.id}`}
            </Text>
            <Text
                className={`rounded-full border border-border-soft-light dark:border-border-soft-dark px-2 py-0.5 text-xs font-open-sans-semibold ${STATUS_TONE_CLASSES[STATUS_TONES[run.status] ?? "neutral"]}`}
            >
                {run.status}
            </Text>
            <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {run.kind === "single" ? "single" : "all bills"}
            </Text>
        </View>
        <Detail label="Bill" value={run.bill_external_id ?? NO_VALUE} />
        <Detail label="Started" value={formatTime(run.started_at)} />
        <Detail label="Completed" value={formatTime(run.completed_at)} />
        <Detail
            label="Bills (succeeded / failed / total)"
            value={`${run.bills_succeeded} / ${run.bills_failed} / ${run.bills_total}`}
        />
        <Detail label="Failing stage" value={run.failing_stage ?? NO_VALUE} />
    </Card>
);

export default function PipelineRunsScreen() {
    const { runs, loading, error, refresh } = usePipelineRuns();

    return (
        <ScrollView
            testID="admin-pipeline-runs-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && runs !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the pipeline runs"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Pipeline Run History
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-pipeline-runs-error" />
            ) : runs === null ? (
                <ActivityIndicator testID="admin-pipeline-runs-loading" className="py-12" />
            ) : runs.length === 0 ? (
                <EmptyState title="No pipeline runs yet." />
            ) : (
                runs.map((run) => <RunCard key={run.id} run={run} />)
            )}
        </ScrollView>
    );
}
