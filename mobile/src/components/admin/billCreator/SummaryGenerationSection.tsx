// @lat: [[mobile-bill-creator#Sections#The summary generation section]]
import React, { useEffect, useState } from "react";
import { Text, TextInput, View } from "react-native";

import { PARITY_COPY } from "../../../../../app/frontend/sway_constants/parityCopy";
import { apiClient } from "../../../api/client";
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

interface SummaryModelOption {
    id: string;
    label: string;
    supports_reasoning?: boolean;
}

interface PreparedPrompt {
    text: string;
    preparedAtStatus: string | null;
}

interface PreparedPromptResponse {
    summary_prompt?: string | null;
    bill?: { bill_pipeline_refresh?: { status?: string | null } | null };
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
const INSTRUCTIONS_LIMIT = 2000;
const REASONING_LEVELS = [
    { value: "", label: "Default" },
    { value: "low", label: "Low" },
    { value: "medium", label: "Medium" },
    { value: "high", label: "High" },
];

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

const trimAscii = (text: string) => text.replace(/^[\x20\t\r\n\f\v]+|[\x20\t\r\n\f\v]+$/g, "");

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

    // @lat: [[mobile-bill-creator#Sections#The summary generation section#Generation options]]
    const modelOptions = (data.summary_model_options ?? []) as SummaryModelOption[];
    const standingModel = (data.current_summarization_model as string | null | undefined) ?? "";
    const standingEffort = (data.current_summarization_reasoning_effort as string | null | undefined) ?? "";
    const [selectedModel, setSelectedModel] = useState<string>(standingModel);
    const [selectedEffort, setSelectedEffort] = useState<string>(standingModel ? standingEffort : "");
    const [instructions, setInstructions] = useState<string>("");

    const offeredOption = (model: string) => modelOptions.find((option) => option.id === model);
    const supportsReasoning = (model: string) => offeredOption(model)?.supports_reasoning === true;
    const activeModel = offeredOption(selectedModel)?.id;

    const chooseModel = (model: string) => {
        if (!supportsReasoning(model)) {
            setSelectedEffort("");
        } else if (model !== selectedModel) {
            setSelectedEffort(model === standingModel ? standingEffort : "");
        }
        setSelectedModel(model);
    };

    const outboundEffort = (): string | undefined => {
        if (!supportsReasoning(selectedModel)) return undefined;
        if (selectedEffort) return selectedEffort;
        if (activeModel && activeModel === standingModel && standingEffort) return "default";
        return undefined;
    };

    const modelAndEffort = (effort: string | undefined) => ({
        ...(activeModel ? { summarization_model: activeModel } : {}),
        ...(effort ? { reasoning_effort: effort } : {}),
    });

    const trimmedInstructions = trimAscii(instructions);
    const instructionsOverLimit = Array.from(trimmedInstructions).length > INSTRUCTIONS_LIMIT;

    // @lat: [[mobile-bill-creator#Sections#The summary generation section#Answering generate and regenerate in JSON]]
    const startRun = async (mutation: typeof generate, body: Record<string, string>) => {
        if ((await mutation.run(body)) === undefined) return false;
        await refresh();
        return true;
    };

    const startGenerate = () => void startRun(generate, modelAndEffort(outboundEffort()));

    const startRegenerate = async () => {
        const body = {
            ...modelAndEffort(outboundEffort()),
            ...(trimmedInstructions ? { summary_instructions: trimmedInstructions } : {}),
        };
        if (await startRun(regenerate, body)) setInstructions("");
    };

    const startEmptyStateGenerate = () =>
        void startRun(regenerate, modelAndEffort(supportsReasoning(selectedModel) ? selectedEffort : undefined));

    const modelPicker = (disabled: boolean) => (
        <ModelPicker
            options={modelOptions}
            activeModel={activeModel}
            onModelChange={chooseModel}
            effort={selectedEffort}
            onEffortChange={setSelectedEffort}
            disabled={disabled}
        />
    );

    const instructionsField = (
        <InstructionsField
            value={instructions}
            onChange={setInstructions}
            count={Array.from(trimmedInstructions).length}
            overLimit={instructionsOverLimit}
            disabled={regenerate.loading}
            modelLabel={offeredOption(selectedModel)?.label ?? null}
        />
    );

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
                {modelPicker(pipelineBusy || regenerate.loading)}
                <RunButton
                    testID="admin-summary-generate"
                    label="Generate summary"
                    busy={regenerate.loading}
                    disabled={pipelineBusy}
                    onPress={startEmptyStateGenerate}
                />
                <PreparePrompt billId={billId} pipelineStatus={pipelineStatus} />
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
            {instructionsField}
            <ConfirmRunButton
                testID="admin-summary-regenerate-latest"
                label="Regenerate from latest data"
                busy={regenerate.loading}
                disabled={(isGenerating && !abandoned) || requestRunning || pipelineBusy || instructionsOverLimit}
                onConfirm={() => void startRegenerate()}
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
                {modelPicker(pipelineBusy || requestRunning || (runInFlight && !abandoned))}
                {!provisioning.stale ? (
                    <>
                        {instructionsField}
                        <ConfirmRunButton
                            testID="admin-summary-regenerate"
                            label="Regenerate summary"
                            busy={regenerate.loading}
                            disabled={
                                pipelineBusy || requestRunning || (runInFlight && !abandoned) || instructionsOverLimit
                            }
                            onConfirm={() => void startRegenerate()}
                        />
                    </>
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
                        {modelPicker(pipelineBusy || requestRunning)}
                        <RunButton
                            testID="admin-summary-generate"
                            label="Generate summary"
                            busy={generate.loading}
                            disabled={pipelineBusy}
                            onPress={startGenerate}
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
            {modelPicker((isPending && !abandoned) || pipelineBusy || requestRunning)}
            <RunButton
                testID="admin-summary-generate"
                label={isFailed ? "Retry" : "Generate summary"}
                busy={generate.loading}
                disabled={(isPending && !abandoned) || pipelineBusy}
                onPress={startGenerate}
            />
            {refusalLine}
        </View>
    );
}

interface ModelPickerProps {
    options: SummaryModelOption[];
    activeModel: string | undefined;
    onModelChange: (model: string) => void;
    effort: string;
    onEffortChange: (effort: string) => void;
    disabled: boolean;
}

const ModelPicker: React.FC<ModelPickerProps> = ({
    options,
    activeModel,
    onModelChange,
    effort,
    onEffortChange,
    disabled,
}) => {
    if (options.length === 0) return null;
    const supportsReasoning = options.find((option) => option.id === activeModel)?.supports_reasoning === true;
    return (
        <View testID="admin-summary-model-picker" className="gap-2">
            <Text className={labelText}>Model for this run</Text>
            {activeModel === undefined ? (
                <Text testID="admin-summary-model-standing" className={mutedText}>
                    Standing default
                </Text>
            ) : null}
            <View className="flex-row flex-wrap gap-2">
                {options.map((option) => (
                    <Pressable
                        key={option.id}
                        testID={`admin-summary-model-${option.id}`}
                        variant={option.id === activeModel ? "default" : "outline"}
                        accessibilityRole="radio"
                        accessibilityState={{ selected: option.id === activeModel }}
                        disabled={disabled}
                        onPress={() => onModelChange(option.id)}
                    >
                        <Text className={labelText}>{option.label}</Text>
                    </Pressable>
                ))}
            </View>
            {supportsReasoning ? (
                <View testID="admin-summary-reasoning" className="gap-2">
                    <Text className={labelText}>Reasoning level for this run</Text>
                    <View className="flex-row flex-wrap gap-2">
                        {REASONING_LEVELS.map((level) => (
                            <Pressable
                                key={level.label}
                                testID={`admin-summary-reasoning-${level.value || "default"}`}
                                variant={level.value === effort ? "default" : "outline"}
                                accessibilityRole="radio"
                                accessibilityState={{ selected: level.value === effort }}
                                disabled={disabled}
                                onPress={() => onEffortChange(level.value)}
                            >
                                <Text className={labelText}>{level.label}</Text>
                            </Pressable>
                        ))}
                    </View>
                </View>
            ) : null}
        </View>
    );
};

interface InstructionsFieldProps {
    value: string;
    onChange: (value: string) => void;
    count: number;
    overLimit: boolean;
    disabled: boolean;
    modelLabel: string | null;
}

const InstructionsField: React.FC<InstructionsFieldProps> = ({
    value,
    onChange,
    count,
    overLimit,
    disabled,
    modelLabel,
}) => (
    <View className="gap-1">
        <Text className={labelText}>Additional instructions (optional)</Text>
        <TextInput
            testID="admin-summary-instructions"
            accessibilityLabel="Additional instructions (optional)"
            placeholder="e.g. Request a missing property tax rate if stated in the bill"
            multiline
            numberOfLines={4}
            value={value}
            onChangeText={onChange}
            editable={!disabled}
            className={`min-h-24 rounded-lg border p-3 ${bodyText} ${
                overLimit
                    ? "border-destructive-light dark:border-destructive-dark"
                    : "border-border-light dark:border-border-dark"
            }`}
        />
        <Text className={mutedText}>
            Instructions apply to this regeneration only. Details must be supported by source material and cannot
            override factual grounding or neutrality.
        </Text>
        <Text testID="admin-summary-instructions-count" className={overLimit ? errorText : mutedText}>
            {`${count.toLocaleString("en-US")} / 2,000`}
        </Text>
        {overLimit ? (
            <Text testID="admin-summary-instructions-error" className={errorText}>
                Instructions exceed the 2,000 code point limit. Please shorten them before regenerating.
            </Text>
        ) : null}
        <Text testID="admin-summary-run-model" className={bodyText}>
            {modelLabel ? `This run uses ${modelLabel}.` : "This run uses the standing default model."}
        </Text>
    </View>
);

const PreparePrompt: React.FC<{ billId: number; pipelineStatus: string | null }> = ({ billId, pipelineStatus }) => {
    const [prompt, setPrompt] = useState<PreparedPrompt | null>(null);
    const [preparing, setPreparing] = useState(false);
    const [failed, setFailed] = useState(false);
    const promptIsStale = prompt !== null && pipelineStatus !== prompt.preparedAtStatus;

    // @lat: [[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]
    const prepare = async () => {
        setPreparing(true);
        setFailed(false);
        try {
            const res = await apiClient.get<PreparedPromptResponse>(Routes.adminBillCreatorSummaryPrompt(billId));
            setPrompt({
                text: res.summary_prompt ?? "",
                preparedAtStatus: res.bill?.bill_pipeline_refresh?.status ?? pipelineStatus,
            });
        } catch {
            setFailed(true);
        } finally {
            setPreparing(false);
        }
    };

    return (
        <View className="gap-3">
            <Pressable
                testID="admin-summary-prepare-prompt"
                variant="outline"
                disabled={preparing}
                onPress={() => void prepare()}
            >
                <Text className={labelText}>{preparing ? "Preparing…" : "Prepare prompt"}</Text>
            </Pressable>
            {failed ? (
                <Text testID="admin-summary-prompt-error" className={errorText}>
                    Could not build the prompt — try again.
                </Text>
            ) : null}
            {prompt ? (
                <Notice testID="admin-summary-prompt" tone="neutral" title="Bill summary prompt">
                    <Text className={bodyText}>
                        Copy this prompt and paste it into another agent. The agent should return JSON with
                        summary_markdown (required), plus optionally full_breakdown_markdown, categories, and
                        cited_section_keys. Any other key is rejected.
                    </Text>
                    <Text testID="admin-summary-prompt-paste-destination" className={bodyText}>
                        When the agent replies, close this prompt and use Paste summary JSON below. No generation is
                        needed, and pasting costs nothing.
                    </Text>
                    {promptIsStale ? (
                        <Notice testID="admin-summary-prompt-stale" tone="danger" title="This prompt is out of date">
                            <Text className={bodyText}>
                                The pipeline changed this bill after the prompt was prepared, so the text below
                                describes an earlier version. Prepare it again before you copy it.
                            </Text>
                        </Notice>
                    ) : null}
                    <Text testID="admin-summary-prompt-text" className={`font-mono ${mutedText}`} selectable>
                        {prompt.text}
                    </Text>
                    <View className="flex-row flex-wrap gap-2">
                        <Pressable
                            testID="admin-summary-prompt-close"
                            variant="outline"
                            onPress={() => setPrompt(null)}
                        >
                            <Text className={labelText}>Close</Text>
                        </Pressable>
                        {promptIsStale ? (
                            <Pressable
                                testID="admin-summary-prompt-reprepare"
                                variant="outline"
                                disabled={preparing}
                                onPress={() => void prepare()}
                            >
                                <Text className={labelText}>{preparing ? "Preparing…" : "Prepare again"}</Text>
                            </Pressable>
                        ) : null}
                    </View>
                </Notice>
            ) : null}
        </View>
    );
};

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
