// @lat: [[mobile-bill-creator#Sections#The pipeline progress section]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { usePolling } from "../../../hooks/admin/usePolling";
import { useTwoTapConfirm } from "../../../hooks/useTwoTapConfirm";
import { exactTime, parseTime, relativeTime } from "../../../utils/runTime";
import { Pressable } from "../../ui/Pressable";

interface PipelineRunStage {
    stage_name: string;
    status: string;
    position: number;
    finished_at: string | null;
}

interface PipelineRun {
    id: number;
    status: string | null;
    kind: "single" | "all_bills" | null;
    error_message: string | null;
    bills_updated: number | null;
    completed_at: string | null;
    abandoned?: boolean | null;
    processed?: number;
    total?: number | null;
    phase?: string | null;
    current_bill_external_id?: string | null;
    eta_seconds?: number | null;
    errors?: { external_id: string; phase: string; message: string }[];
    queued?: string[];
    pipeline_run_stages?: PipelineRunStage[];
}

const POLL_INTERVAL_MS = 5000;

const STAGE_STATUS_LABELS: Record<string, string> = {
    fetching_bills: "Fetching bills",
    fetching_law: "Fetching law",
    extracting_text: "Extracting text",
    parsing_sections: "Parsing sections",
    generating_diffs: "Generating diffs",
    fetching_hearings: "Fetching hearings",
    cleaning_testimony: "Cleaning testimony",
    summarizing: "Summarizing",
    awaiting_summary_batch: "Awaiting summary batch",
};

const IN_FLIGHT_STATUSES = ["queued", "running", ...Object.keys(STAGE_STATUS_LABELS)];

const PHASE_LABELS: Record<string, string> = {
    downloading: "Downloading PDFs",
    extracting: "Extracting text",
    saving: "Saving to database",
};

const STATUS_LABELS: Record<string, string> = {
    completed: "Done",
    succeeded: "Succeeded",
    partial: "Partial",
    failed: "Failed",
    cancelled: "Cancelled",
    running: "Running",
    queued: "Queued",
    ...STAGE_STATUS_LABELS,
};

export const isInFlight = (status: string | null | undefined) =>
    typeof status === "string" && IN_FLIGHT_STATUSES.includes(status);

const statusLabel = (run: PipelineRun) => {
    if (run.status === "failed" && run.error_message?.startsWith("empty_artifact:")) return "Failed — no output";
    return run.status ? (STATUS_LABELS[run.status] ?? run.status) : "Unknown status";
};

const failureTiming = (iso: string | null | undefined) => {
    const date = parseTime(iso);
    return date ? `Failed ${relativeTime(date)} — ${exactTime(iso)}` : null;
};

const formatEta = (seconds: number) => {
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
};

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";

const TONE_CLASSES = {
    success: "text-success-light dark:text-success-dark",
    warning: "text-warning-foreground-light dark:text-warning-foreground-dark",
    danger: "text-destructive-light dark:text-destructive-dark",
};

interface AlertProps {
    testID: string;
    tone: keyof typeof TONE_CLASSES;
    title: string;
    children: React.ReactNode;
}

const Alert: React.FC<AlertProps> = ({ testID, tone, title, children }) => (
    <View testID={testID} className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1">
        <Text className={`text-sm font-open-sans-semibold ${TONE_CLASSES[tone]}`}>{title}</Text>
        {children}
    </View>
);

interface DisclosureProps {
    testID: string;
    title: string;
    initiallyOpen: boolean;
    children: React.ReactNode;
}

const Disclosure: React.FC<DisclosureProps> = ({ testID, title, initiallyOpen, children }) => {
    const [open, setOpen] = useState(initiallyOpen);
    return (
        <View>
            <Pressable
                testID={`${testID}-toggle`}
                variant="ghost"
                accessibilityState={{ expanded: open }}
                onPress={() => setOpen(!open)}
                className="justify-start px-0"
            >
                <Text className={labelText}>{title}</Text>
            </Pressable>
            {open ? children : null}
        </View>
    );
};

interface CancelRunButtonProps {
    runId: number;
    abandoned: boolean;
    refresh: () => Promise<void>;
}

const CancelRunButton: React.FC<CancelRunButtonProps> = ({ runId, abandoned, refresh }) => {
    const { confirming, arm, disarm } = useTwoTapConfirm();
    const { run, loading, errorMessage } = useAdminMutation<unknown>("delete", Routes.adminPipelineRunCancel(runId));

    const press = async () => {
        if (!confirming) {
            arm();
            return;
        }
        disarm();
        if ((await run()) === undefined) return;
        await refresh();
    };

    const label = confirming
        ? abandoned
            ? "Tap again to clear"
            : "Tap again to cancel"
        : abandoned
          ? "Clear this run"
          : "Cancel run";

    return (
        <View className="gap-1">
            <Pressable
                testID="admin-pipeline-cancel"
                variant={confirming ? "destructive" : "outline"}
                disabled={loading}
                onPress={() => void press()}
            >
                <Text className={labelText}>{label}</Text>
            </Pressable>
            {errorMessage ? (
                <Text testID="admin-pipeline-cancel-error" className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
        </View>
    );
};

const failureRemedy = (run: PipelineRun, billId: number | null) => {
    if (run.kind === "single") {
        return "use Resume above to try the failed stage again, or Restart to run it from the beginning.";
    }
    return billId !== null && billId > 0
        ? "the bill picker above holds one bill, so Run pipeline starts a run for that bill alone."
        : "pick the stages above and click Run pipeline, which starts a run over every bill.";
};

export default function PipelineProgressSection({ billId, data, refresh }: BillCreatorTabProps) {
    const run = (data.legislation_pipeline_run ?? null) as PipelineRun | null;
    const billRefresh = (data.bill as { bill_pipeline_refresh?: { status?: string } | null } | undefined)
        ?.bill_pipeline_refresh;
    const billRefreshing = billRefresh?.status === "queued" || billRefresh?.status === "running";
    usePolling(refresh, isInFlight(run?.status) || billRefreshing, POLL_INTERVAL_MS);

    if (!run) {
        return (
            <View testID="admin-pipeline-progress" className="px-4 mt-6">
                <Text className={mutedText}>
                    No pipeline run yet. Select stages and click Run pipeline to start ingestion.
                </Text>
            </View>
        );
    }

    const { processed = 0, total = null, phase = null, errors = [], queued = [] } = run;
    const percent = total && total > 0 ? (processed / total) * 100 : 0;
    const abandoned = run.abandoned === true;
    const failedSingle = run.status === "failed" && run.kind === "single";
    const stages = run.pipeline_run_stages ?? [];
    const timing = failureTiming(run.completed_at);
    const cancelledAt = exactTime(run.completed_at);

    return (
        <View testID="admin-pipeline-progress" className="px-4 mt-6 gap-3">
            <View className="flex-row flex-wrap items-center gap-2">
                <Text testID="admin-pipeline-status" className={`uppercase ${labelText}`}>
                    {statusLabel(run)}
                </Text>
                {run.status === "running" && errors.length > 0 ? (
                    <Text testID="admin-pipeline-error-count" className={TONE_CLASSES.warning}>
                        {errors.length} bill error(s)
                    </Text>
                ) : null}
                {phase ? (
                    <Text testID="admin-pipeline-phase" className={`uppercase ${mutedText}`}>
                        {PHASE_LABELS[phase] ?? phase}
                    </Text>
                ) : null}
            </View>

            {abandoned ? (
                <Text testID="admin-pipeline-abandoned-notice" className={mutedText}>
                    Nothing is working on this run — no worker is carrying it, and nothing has written to it for hours.
                    Clearing it frees the Run button. Resume then starts again at the stage it stopped in.
                </Text>
            ) : null}

            {isInFlight(run.status) && !abandoned ? (
                <View
                    testID="admin-pipeline-progress-bar"
                    accessibilityRole="progressbar"
                    accessibilityValue={{ min: 0, max: 100, now: Math.round(percent) }}
                    className="h-3 overflow-hidden rounded-full bg-muted-light dark:bg-muted-dark"
                >
                    <View
                        testID="admin-pipeline-progress-bar-fill"
                        className="h-3 rounded-full bg-primary-light dark:bg-primary-dark"
                        style={{ width: `${percent}%` }}
                    />
                </View>
            ) : null}

            {run.status === "running" ? (
                <View className="gap-1">
                    <Text testID="admin-pipeline-current-bill" className={labelText}>
                        {run.current_bill_external_id ?? "—"}
                    </Text>
                    {run.eta_seconds != null ? (
                        <Text testID="admin-pipeline-eta" className={`uppercase ${mutedText}`}>
                            ~{formatEta(run.eta_seconds)} remaining
                        </Text>
                    ) : null}
                    <Text className={mutedText}>
                        {processed} / {total ?? "?"} bills
                    </Text>
                    {queued.length > 0 ? (
                        <Disclosure
                            testID="admin-pipeline-queue"
                            title={`Queue (${queued.length} remaining)`}
                            initiallyOpen={false}
                        >
                            <View testID="admin-pipeline-queued-list">
                                {queued.map((id) => (
                                    <Text key={id} className={mutedText}>
                                        {id}
                                    </Text>
                                ))}
                            </View>
                        </Disclosure>
                    ) : null}
                </View>
            ) : null}

            {errors.length > 0 ? (
                <Disclosure
                    testID="admin-pipeline-errors"
                    title={`Errors (${errors.length})`}
                    initiallyOpen={run.status === "failed"}
                >
                    <View testID="admin-pipeline-errors-list">
                        {errors.map((e, i) => (
                            <Text key={i} className={errorText}>
                                {`${e.external_id} — ${e.phase}: ${e.message}`}
                            </Text>
                        ))}
                    </View>
                </Disclosure>
            ) : null}

            {run.status === "completed" ? (
                <Alert testID="admin-pipeline-success-alert" tone="success" title="Pipeline complete">
                    <Text className={bodyText}>{run.bills_updated ?? 0} bill(s) updated.</Text>
                </Alert>
            ) : null}

            {run.status === "succeeded" ? (
                <Alert testID="admin-pipeline-succeeded-alert" tone="success" title="Run succeeded">
                    <Text className={bodyText}>All bills processed successfully.</Text>
                </Alert>
            ) : null}

            {run.status === "partial" ? (
                <Alert testID="admin-pipeline-partial-alert" tone="warning" title="Run completed with failures">
                    <Text className={bodyText}>Some bills failed. See the summary above for details.</Text>
                </Alert>
            ) : null}

            {failedSingle && stages.length > 0 ? (
                <View testID="admin-pipeline-cached-stages" className="gap-1">
                    {stages.map((stage) => (
                        <View key={`${stage.position}-${stage.stage_name}`} className="flex-row flex-wrap gap-2">
                            <Text className={mutedText}>{stage.position}.</Text>
                            <Text className={labelText}>{stage.stage_name}</Text>
                            {stage.status === "succeeded" ? (
                                <Text accessibilityLabel="Stage already succeeded" className={mutedText}>
                                    succeeded
                                </Text>
                            ) : null}
                            {stage.status === "failed" ? <Text className={TONE_CLASSES.danger}>failed</Text> : null}
                            {stage.status === "failed" && exactTime(stage.finished_at) ? (
                                <Text className={mutedText}>{exactTime(stage.finished_at)}</Text>
                            ) : null}
                        </View>
                    ))}
                </View>
            ) : null}

            {run.status === "failed" ? (
                <Alert testID="admin-pipeline-error-alert" tone="danger" title="Pipeline failed">
                    <Text className={bodyText}>
                        {phase ? `During ${PHASE_LABELS[phase] ?? phase}: ` : ""}
                        {run.error_message ?? "Unknown error"} — {failureRemedy(run, billId)}
                    </Text>
                    {timing ? (
                        <Text testID="admin-pipeline-failure-timing" className={bodyText}>
                            {timing}
                        </Text>
                    ) : null}
                </Alert>
            ) : null}

            {run.status === "cancelled" ? (
                <Alert testID="admin-pipeline-cancelled-alert" tone="warning" title="Run cancelled">
                    <Text className={bodyText}>
                        {cancelledAt ? `Cancelled at ${cancelledAt}. ` : ""}
                        {processed} of {total ?? "?"} bills processed before cancel.
                    </Text>
                </Alert>
            ) : null}
            {isInFlight(run.status) ? (
                <CancelRunButton key={run.id} runId={run.id} abandoned={abandoned} refresh={refresh} />
            ) : null}
        </View>
    );
}
