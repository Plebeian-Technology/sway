// @lat: [[mobile-bill-creator#Sections#The summary generation section]]
import React, { useEffect, useState } from "react";
import { Text, View } from "react-native";

import { PARITY_COPY } from "../../../../../app/frontend/sway_constants/parityCopy";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { usePolling } from "../../../hooks/admin/usePolling";
import { useTwoTapConfirm } from "../../../hooks/useTwoTapConfirm";
import { parseTime, relativeTime } from "../../../utils/runTime";
import { Markdown } from "../../Markdown";
import { Pressable } from "../../ui/Pressable";

type GenerationStatus = "pending" | "generating" | "completed" | "failed" | "skipped" | null;

interface Provisioning {
    generation_status: GenerationStatus;
    generation_error: string | null;
    llm_summary: string | null;
    llm_full_breakdown: string | null;
    llm_provider: string | null;
    stale: boolean;
    stale_change_kind: "testimony" | "pipeline_data" | null;
    stale_change_at: string | null;
    reclaimable: boolean;
    paste_owns_summary_run: boolean;
    has_testimony: boolean;
    citations_valid: boolean | null;
    invalid_citations: string[] | null;
}

interface SummaryBill {
    external_id?: string | null;
    summary?: string | null;
    summary_ai_unreviewed?: boolean;
    bill_llm_provisioning?: Provisioning | null;
    bill_pipeline_refresh?: { status?: string | null } | null;
    bill_pipeline_last_failure?: { run_id: number; error_message: string | null; failed_at: string } | null;
}

interface ActiveRun {
    status?: string | null;
    bill_id?: number | null;
}

const POLL_INTERVAL_MS = 5000;
const NO_PROVISIONING_POLL_ATTEMPTS = 12;
const TERMINAL_RUN_STATUSES = ["completed", "succeeded", "partial", "failed", "cancelled"];
const OPERATOR_PASTE_PROVIDER = "operator_paste";
const SUMMARY_PLACEHOLDER = "Summary pending";
const BUSY_LABEL = "Queueing…";

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";

const TONE_CLASSES = {
    neutral: "text-muted-foreground-light dark:text-muted-foreground-dark",
    primary: "text-primary-light dark:text-primary-dark",
    success: "text-success-light dark:text-success-dark",
    warning: "text-warning-foreground-light dark:text-warning-foreground-dark",
    danger: "text-destructive-light dark:text-destructive-dark",
};

type Tone = keyof typeof TONE_CLASSES;

interface NoticeProps {
    testID: string;
    tone: Tone;
    title: string;
    children: React.ReactNode;
}

const Notice: React.FC<NoticeProps> = ({ testID, tone, title, children }) => (
    <View testID={testID} className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1">
        <Text className={`text-sm font-open-sans-semibold ${TONE_CLASSES[tone]}`}>{title}</Text>
        {children}
    </View>
);

const badgeFor = (status: GenerationStatus, abandoned: boolean): { label: string; tone: Tone } => {
    if (abandoned && (status === "pending" || status === "generating")) return { label: "Abandoned", tone: "warning" };
    if (status === "completed") return { label: "Ready", tone: "success" };
    if (status === "failed") return { label: "Failed", tone: "danger" };
    if (status === "pending") return { label: "Queued…", tone: "neutral" };
    if (status === "generating") return { label: "Generating…", tone: "primary" };
    if (status === "skipped") return { label: "Skipped", tone: "neutral" };
    return { label: "Not generated", tone: "neutral" };
};

const StatusBadge: React.FC<{ status: GenerationStatus; abandoned: boolean; pasted?: boolean }> = ({
    status,
    abandoned,
    pasted = false,
}) => {
    const { label, tone } = badgeFor(status, abandoned);
    return (
        <View className="flex-row flex-wrap items-center gap-2">
            <Text
                testID="admin-summary-status"
                className={`uppercase text-xs font-open-sans-semibold ${TONE_CLASSES[tone]}`}
            >
                {label}
            </Text>
            {pasted ? (
                <Text
                    testID="admin-summary-pasted"
                    className={`uppercase text-xs font-open-sans-semibold ${TONE_CLASSES.warning}`}
                >
                    Operator-pasted
                </Text>
            ) : null}
        </View>
    );
};

const staleChangeLabel = (kind: Provisioning["stale_change_kind"], at: string | null) => {
    const date = parseTime(at);
    if (kind === null || !date) return "Stale: last update unknown";
    return `Stale: ${kind === "testimony" ? "testimony" : "pipeline data"} updated ${relativeTime(date)}`;
};

const abandonedNoticeText = (status: GenerationStatus, hasTestimony: boolean) =>
    (status === "pending"
        ? "This run never started, and nothing is working on it now. "
        : "This run stopped part-way, and nothing is working on it now. ") +
    "Starting a new run takes it over. " +
    (hasTestimony
        ? "It costs no more than two model calls: one for the summary, one for the organization positions."
        : "This bill has no testimony, so a run asks for no organization positions. It costs no more than one " +
          "model call, for the summary.");

const draftPredicate = (hasDraft: boolean) =>
    hasDraft ? " A draft summary is still on this bill. The summary below is the published one." : "";

interface RunButtonProps {
    testID: string;
    label: string;
    busy: boolean;
    disabled: boolean;
    onPress: () => void;
    variant?: "default" | "outline";
}

const RunButton: React.FC<RunButtonProps> = ({ testID, label, busy, disabled, onPress, variant = "default" }) => (
    <Pressable testID={testID} variant={variant} disabled={busy || disabled} onPress={onPress}>
        <Text className={labelText}>{busy ? BUSY_LABEL : label}</Text>
    </Pressable>
);

interface ConfirmRunButtonProps extends Omit<RunButtonProps, "onPress" | "variant"> {
    onConfirm: () => void;
}

const ConfirmRunButton: React.FC<ConfirmRunButtonProps> = ({ testID, label, busy, disabled, onConfirm }) => {
    const { confirming, arm, disarm } = useTwoTapConfirm();
    const press = () => {
        if (!confirming) {
            arm();
            return;
        }
        disarm();
        onConfirm();
    };
    return (
        <RunButton
            testID={testID}
            label={confirming ? "Tap again to regenerate" : label}
            busy={busy}
            disabled={disabled}
            onPress={press}
            variant={confirming ? "default" : "outline"}
        />
    );
};

const reasonFor = (fieldErrors: Record<string, unknown> | null, errorMessage: string | null) =>
    typeof fieldErrors?.generation === "string" ? fieldErrors.generation : errorMessage;

const isPublished = (summary: string | null | undefined) => {
    const text = (summary ?? "").trim();
    return text !== "" && text !== SUMMARY_PLACEHOLDER;
};

export default function SummaryGenerationSection({ billId, data, refresh }: BillCreatorTabProps) {
    const bill = (data.bill ?? {}) as SummaryBill;
    const provisioning = bill.bill_llm_provisioning ?? null;
    const status = provisioning?.generation_status ?? null;
    const pipelineStatus = bill.bill_pipeline_refresh?.status ?? null;
    const pipelineBusy = pipelineStatus !== null && !TERMINAL_RUN_STATUSES.includes(pipelineStatus);
    const isGenerating = status === "pending" || status === "generating";

    const [spentWatchBillId, setSpentWatchBillId] = useState<number | null>(null);
    const hasNoProvisioning = billId !== null && !provisioning;
    useEffect(() => {
        if (!hasNoProvisioning) return undefined;
        const timer = setTimeout(() => setSpentWatchBillId(billId), NO_PROVISIONING_POLL_ATTEMPTS * POLL_INTERVAL_MS);
        return () => clearTimeout(timer);
    }, [hasNoProvisioning, billId]);
    const watchingNoProvisioning = hasNoProvisioning && spentWatchBillId !== billId;

    // @lat: [[mobile-bill-creator#Sections#The summary generation section#Polling while a summary is generated]]
    usePolling(refresh, billId !== null && (isGenerating || watchingNoProvisioning || pipelineBusy), POLL_INTERVAL_MS);

    const generate = useAdminMutation<unknown>("post", Routes.billGenerateSummary(billId ?? 0));
    const regenerate = useAdminMutation<unknown>("post", Routes.billRegenerateSummary(billId ?? 0));
    const requestRunning = generate.loading || regenerate.loading;
    const refusal =
        reasonFor(generate.fieldErrors, generate.errorMessage) ??
        reasonFor(regenerate.fieldErrors, regenerate.errorMessage);

    // @lat: [[mobile-bill-creator#Sections#The summary generation section#Answering generate and regenerate in JSON]]
    const startRun = async (mutation: typeof generate) => {
        if ((await mutation.run()) === undefined) return;
        await refresh();
    };

    if (billId === null) {
        return (
            <View testID="admin-summary-generation" className="px-4 mt-6">
                <Text className={mutedText}>Save this bill before generating its summary.</Text>
            </View>
        );
    }

    const abandoned = provisioning?.reclaimable === true;
    const hasDraft = Boolean(provisioning?.llm_summary);
    const activeRun = (data.active_legislation_pipeline_run ?? null) as ActiveRun | null;
    const cleanTestimonyRunning =
        activeRun?.status === "cleaning_testimony" && (activeRun.bill_id == null || activeRun.bill_id === billId);
    const runInFlight = isGenerating || cleanTestimonyRunning;

    const pipelineBusyLine = pipelineBusy ? (
        <Text testID="admin-summary-pipeline-busy" className={`uppercase ${mutedText}`}>
            {pipelineStatus === "queued"
                ? "Generation is unavailable until this pipeline run starts and finishes."
                : "Generation is unavailable until this pipeline run finishes."}
        </Text>
    ) : null;

    const refusalLine = refusal ? (
        <Text testID="admin-summary-error" className={errorText}>
            {refusal}
        </Text>
    ) : null;

    if (!provisioning) {
        const failure = bill.bill_pipeline_last_failure ?? null;
        return (
            <View testID="admin-summary-generation" className="px-4 mt-6 gap-3">
                <Text testID="admin-summary-no-pipeline-data" className={mutedText}>
                    No pipeline data available. Run the legislation pipeline for this bill first.
                </Text>
                <RunButton
                    testID="admin-summary-generate"
                    label="Generate summary"
                    busy={regenerate.loading}
                    disabled={pipelineBusy}
                    onPress={() => void startRun(regenerate)}
                />
                {refusalLine}
                {pipelineBusyLine}
                {failure ? (
                    <Notice testID="admin-summary-pipeline-failure" tone="danger" title="Pipeline failed">
                        <Text className={bodyText}>
                            {`${bill.external_id ?? ""}: ${failure.error_message || "no reason recorded"}`}
                            {" — open this run on the Pipeline tab to resume or restart it."}
                        </Text>
                    </Notice>
                ) : null}
            </View>
        );
    }

    const staleHeader = provisioning.stale ? (
        <View
            testID="admin-summary-stale"
            className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-2"
        >
            <Text className={labelText}>Summary is out of date</Text>
            <Text className={`uppercase text-xs font-open-sans-semibold ${TONE_CLASSES.warning}`}>
                {staleChangeLabel(provisioning.stale_change_kind, provisioning.stale_change_at)}
            </Text>
            <ConfirmRunButton
                testID="admin-summary-regenerate-latest"
                label="Regenerate from latest data"
                busy={regenerate.loading}
                disabled={(isGenerating && !abandoned) || requestRunning || pipelineBusy}
                onConfirm={() => void startRun(regenerate)}
            />
        </View>
    ) : null;

    if (status === "completed" || hasDraft) {
        return (
            <View testID="admin-summary-generation" className="px-4 mt-6 gap-3">
                {pipelineBusyLine}
                {staleHeader}
                <InFlightNotice provisioning={provisioning} abandoned={abandoned} />
                {provisioning.citations_valid === false && provisioning.invalid_citations?.length ? (
                    <Notice
                        testID="admin-summary-citation-warning"
                        tone="warning"
                        title={`Unverified citation${provisioning.invalid_citations.length > 1 ? "s" : ""}`}
                    >
                        <Text className={bodyText}>
                            {`This summary cites section key${provisioning.invalid_citations.length > 1 ? "s" : ""} not found in the bill's parsed sections: ${provisioning.invalid_citations.join(", ")}. Review before publishing — this does not block saving or approving.`}
                        </Text>
                    </Notice>
                ) : null}
                {status === "failed" && provisioning.generation_error ? (
                    <Notice testID="admin-summary-failed" tone="danger" title="Summary generation failed">
                        <Text className={bodyText}>
                            {provisioning.generation_error}
                            {draftPredicate(hasDraft)}
                        </Text>
                    </Notice>
                ) : null}
                <SkippedNotice provisioning={provisioning} hasDraft={hasDraft} />
                <StatusBadge
                    status={status}
                    abandoned={abandoned}
                    pasted={provisioning.llm_provider === OPERATOR_PASTE_PROVIDER}
                />
                <PublishedSummary bill={bill} />
                <DraftNotice provisioning={provisioning} publishedSummary={bill.summary ?? ""} />
                {!provisioning.stale ? (
                    <ConfirmRunButton
                        testID="admin-summary-regenerate"
                        label="Regenerate summary"
                        busy={regenerate.loading}
                        disabled={pipelineBusy || requestRunning || (runInFlight && !abandoned)}
                        onConfirm={() => void startRun(regenerate)}
                    />
                ) : null}
                {refusalLine}
                <Breakdown breakdown={provisioning.llm_full_breakdown} />
            </View>
        );
    }

    if (status === "generating") {
        return (
            <View testID="admin-summary-generation" className="px-4 mt-6 gap-3">
                {pipelineBusyLine}
                {staleHeader}
                <StatusBadge status={status} abandoned={abandoned} />
                {abandoned ? (
                    <>
                        <Text testID="admin-summary-abandoned" className={bodyText}>
                            {abandonedNoticeText(status, provisioning.has_testimony)}
                        </Text>
                        <RunButton
                            testID="admin-summary-generate"
                            label="Generate summary"
                            busy={generate.loading}
                            disabled={pipelineBusy}
                            onPress={() => void startRun(generate)}
                        />
                    </>
                ) : (
                    <>
                        <Text testID="admin-summary-generating" className={`italic ${mutedText}`}>
                            Generating summary…
                        </Text>
                        <RunButton
                            testID="admin-summary-generate"
                            label="Generating…"
                            busy={false}
                            disabled
                            onPress={() => {}}
                        />
                    </>
                )}
                {refusalLine}
            </View>
        );
    }

    const isPending = status === "pending";
    const isFailed = status === "failed";
    return (
        <View testID="admin-summary-generation" className="px-4 mt-6 gap-3">
            {pipelineBusyLine}
            {staleHeader}
            <StatusBadge status={status} abandoned={abandoned} />
            {isFailed ? (
                <Notice testID="admin-summary-failed" tone="danger" title="Summary generation failed">
                    <Text className={bodyText}>{provisioning.generation_error || "Sway did not record a reason."}</Text>
                </Notice>
            ) : null}
            {abandoned ? (
                <Text testID="admin-summary-abandoned" className={bodyText}>
                    {abandonedNoticeText(status, provisioning.has_testimony)}
                </Text>
            ) : null}
            {isPending && !abandoned ? (
                <Notice testID="admin-summary-queued-notice" tone="neutral" title="A new summary is queued">
                    <Text className={bodyText}>
                        Sway is waiting for a worker to pick this run up, and then the run itself takes a couple of
                        minutes. This panel updates itself while you wait, so there is nothing to tap.
                    </Text>
                </Notice>
            ) : null}
            <SkippedNotice provisioning={provisioning} hasDraft={false} />
            <RunButton
                testID="admin-summary-generate"
                label={isFailed ? "Retry" : "Generate summary"}
                busy={generate.loading}
                disabled={(isPending && !abandoned) || pipelineBusy}
                onPress={() => void startRun(generate)}
            />
            {refusalLine}
        </View>
    );
}

const InFlightNotice: React.FC<{ provisioning: Provisioning; abandoned: boolean }> = ({ provisioning, abandoned }) => {
    const status = provisioning.generation_status;
    if (status !== "pending" && status !== "generating") return null;
    if (!provisioning.llm_summary) return null;

    const held =
        provisioning.llm_provider === OPERATOR_PASTE_PROVIDER
            ? "the summary you pasted"
            : status === "pending"
              ? "the draft summary from the last run"
              : "the draft summary on this bill";
    const abandonedRunFate = status === "pending" ? "The new run never started" : "This run stopped part-way";
    const sweepSettlesThePaste = abandoned && provisioning.paste_owns_summary_run;

    const title = sweepSettlesThePaste
        ? "Nothing is working on this row"
        : abandoned
          ? abandonedRunFate
          : status === "pending"
            ? "A new summary is queued"
            : "A new summary is being written";
    const fate = sweepSettlesThePaste
        ? "Nothing is working on this row now. Sway settles a summary you pasted on its own and keeps your text, so " +
          "there is nothing to do. Regenerating would replace it. "
        : abandoned
          ? `${abandonedRunFate}, and nothing is working on it now. Regenerate to start a new one. `
          : "The new run replaces it when it finishes. ";

    return (
        <Notice testID="admin-summary-in-flight" tone="primary" title={title}>
            <Text className={bodyText}>
                {`You are looking at ${held}. ${fate}The published summary below is not changed by a run.`}
            </Text>
        </Notice>
    );
};

const SkippedNotice: React.FC<{ provisioning: Provisioning; hasDraft: boolean }> = ({ provisioning, hasDraft }) => {
    if (provisioning.generation_status !== "skipped") return null;
    return (
        <Notice testID="admin-summary-skipped" tone="warning" title="This run was dropped">
            <Text className={bodyText}>
                {provisioning.generation_error ||
                    "It waited in the queue too long, so the worker passed it over. Nothing failed. Try again when you are ready."}
                {draftPredicate(hasDraft)}
            </Text>
        </Notice>
    );
};

const PublishedSummary: React.FC<{ bill: SummaryBill }> = ({ bill }) => {
    if (!isPublished(bill.summary)) {
        return (
            <Text testID="admin-summary-published-empty" className={mutedText}>
                No summary is published on this bill yet.
            </Text>
        );
    }
    return (
        <View className="gap-2">
            <Markdown testID="admin-summary-published" content={bill.summary} className={bodyText} selectable />
            {bill.summary_ai_unreviewed ? (
                <Text testID="admin-summary-ai-unreviewed" className={mutedText}>
                    {PARITY_COPY.bill.aiUnreviewedNotice}
                </Text>
            ) : null}
        </View>
    );
};

const DraftNotice: React.FC<{ provisioning: Provisioning; publishedSummary: string }> = ({
    provisioning,
    publishedSummary,
}) => {
    const draft = provisioning.llm_summary ?? "";
    if (!draft || draft === publishedSummary) return null;
    const pasted = provisioning.llm_provider === OPERATOR_PASTE_PROVIDER;
    return (
        <Notice
            testID="admin-summary-draft"
            tone="primary"
            title={pasted ? "Your pasted summary is not on the bill yet" : "The model wrote a different summary"}
        >
            <Text className={bodyText}>
                {pasted ? "This is the text you pasted." : "This is the draft from the last run."} It is not on the
                bill.
            </Text>
            <Markdown content={draft} className={bodyText} selectable />
        </Notice>
    );
};

const Breakdown: React.FC<{ breakdown: string | null }> = ({ breakdown }) => {
    const [open, setOpen] = useState(false);
    if (!(breakdown ?? "").trim()) {
        return (
            <Text testID="admin-summary-breakdown-absent" className={mutedText}>
                This run wrote no section breakdown. The breakdown is an optional part of the model’s answer, and a run
                that leaves it out still writes the public summary.
            </Text>
        );
    }
    return (
        <View className="gap-2">
            <Pressable
                testID="admin-summary-breakdown-toggle"
                variant="ghost"
                accessibilityState={{ expanded: open }}
                onPress={() => setOpen(!open)}
                className="justify-start px-0"
            >
                <Text className={labelText}>
                    {open ? "Hide full section breakdown" : "Show full section breakdown"}
                </Text>
            </Pressable>
            {open ? (
                <Text testID="admin-summary-breakdown" className={mutedText} selectable>
                    {breakdown}
                </Text>
            ) : null}
        </View>
    );
};
