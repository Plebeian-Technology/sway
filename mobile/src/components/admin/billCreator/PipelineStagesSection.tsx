// @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import { usePipelinePreview, type PipelinePreview } from "../../../hooks/admin/usePipelinePreview";
import { useBootstrap } from "../../../state/BootstrapContext";
import { Pressable } from "../../ui/Pressable";

const STAGES = [
    { key: "fetch-bills", label: "Fetch bills", subtext: "Downloads bill metadata + PDFs from Legistar (network)" },
    { key: "fetch-law", label: "Fetch law", subtext: "Downloads/refreshes statutory law corpus (network)" },
    {
        key: "extract-text",
        label: "Extract text",
        subtext: "Runs OCR (tesseract) on the downloaded PDFs — this is the slow one you're watching",
    },
    {
        key: "parse-sections",
        label: "Parse sections",
        subtext:
            "Takes the OCR'd text and splits it into structured sections (§ 4-101, etc.) using fuzzy matching — pure CPU on already-extracted text",
    },
    {
        key: "generate-diffs",
        label: "Generate diffs",
        subtext: "Computes added/removed/modified text between current bill and prior law",
    },
    { key: "fetch-hearings", label: "Fetch hearings", subtext: "Hits Legistar for hearing schedules (network)" },
    {
        key: "clean-testimony",
        label: "Process testimony",
        subtext:
            "Clean, repair, split, group, classify (speaker + stance), and extract organization entities from fetched hearing testimony",
    },
    {
        key: "summarize-bill",
        label: "Summarize bill",
        subtext: "Generate LLM summary + reasoning per bill (calls llama.cpp)",
    },
] as const;

export const ALL_STAGE_KEYS: string[] = STAGES.map((s) => s.key);

const DEFAULT_STAGE_KEYS: string[] = ALL_STAGE_KEYS.filter((key) => key !== "summarize-bill");

const REDUCED_WHEN_AUTO_INCLUDED = [
    "fetch-bills",
    "extract-text",
    "parse-sections",
    "generate-diffs",
    "fetch-hearings",
    "clean-testimony",
    "summarize-bill",
];

const titleize = (text: string) =>
    text
        .toLowerCase()
        .split(" ")
        .filter(Boolean)
        .map((word) => word[0].toUpperCase() + word.slice(1))
        .join(" ");

const stageName = (key: string) => STAGES.find((s) => s.key === key)?.label ?? key;

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const errorText = "text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";

interface CheckRowProps {
    testID: string;
    label: string;
    subtext: string;
    checked: boolean;
    disabled?: boolean;
    onPress: () => void;
}

const CheckRow: React.FC<CheckRowProps> = ({ testID, label, subtext, checked, disabled = false, onPress }) => (
    <Pressable
        testID={testID}
        variant="ghost"
        accessibilityRole="checkbox"
        accessibilityState={{ checked }}
        accessibilityLabel={label}
        disabled={disabled}
        onPress={onPress}
        className="flex-row items-start justify-start gap-3 px-0"
    >
        <Text className={`w-5 ${labelText}`}>{checked ? "✓" : "○"}</Text>
        <View className="flex-1">
            <Text className={labelText}>{label}</Text>
            <Text className={mutedText}>{subtext}</Text>
        </View>
    </Pressable>
);

export default function PipelineStagesSection({ billId, data, refresh }: BillCreatorTabProps) {
    const { bootstrap } = useBootstrap();
    const locale = bootstrap?.locale ?? null;
    const [selectedStages, setSelectedStages] = useState<string[]>(
        () => (data.selected_stages as string[] | undefined) ?? DEFAULT_STAGE_KEYS,
    );
    const [downloadMissingAssets, setDownloadMissingAssets] = useState(data.download_missing_assets !== false);
    const [queued, setQueued] = useState(false);
    const { preview, load } = usePipelinePreview(billId, (data.pipeline_preview ?? null) as PipelinePreview | null);
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>("post", Routes.adminRunPipeline());

    const changeSelection = (stages: string[], dma: boolean) => {
        setSelectedStages(stages);
        setDownloadMissingAssets(dma);
        setQueued(false);
        void load(stages, dma);
    };

    const toggleStage = (key: string) =>
        changeSelection(
            selectedStages.includes(key) ? selectedStages.filter((s) => s !== key) : [...selectedStages, key],
            downloadMissingAssets,
        );

    const selectedCount = STAGES.filter((s) => selectedStages.includes(s.key)).length;
    const bothFetchesSelected = selectedStages.includes("fetch-bills") && selectedStages.includes("fetch-hearings");
    const hasSelection = selectedStages.length > 0;
    const reducedAutoIncluded = (preview?.stages_auto_included ?? []).filter((stage) =>
        REDUCED_WHEN_AUTO_INCLUDED.includes(stage),
    );
    const prereqViolations = preview?.prereq_violations ?? [];
    const pipelineError = typeof fieldErrors?.pipeline === "string" ? fieldErrors.pipeline : errorMessage;
    const billExternalId = data.bill?.external_id;

    const startRun = async () => {
        setQueued(false);
        const response = await run({
            stages: selectedStages,
            bill_id: billId,
            sway_locale_id: locale?.id ?? null,
            download_missing_assets: downloadMissingAssets,
        });
        if (response === undefined) return;
        setQueued(true);
        await refresh();
    };

    return (
        <View testID="admin-pipeline-stages" className="px-4 mt-6">
            <View className="flex-row flex-wrap items-center justify-between gap-2">
                <Text className={`uppercase ${labelText}`}>Stages to run</Text>
                <Text className={mutedText}>
                    {selectedCount} of {STAGES.length} selected
                </Text>
            </View>
            <View className="flex-row gap-2 mt-2">
                <Pressable
                    testID="admin-pipeline-select-all"
                    variant="outline"
                    disabled={selectedCount === STAGES.length}
                    onPress={() => changeSelection(ALL_STAGE_KEYS, downloadMissingAssets)}
                >
                    <Text className={labelText}>Select all</Text>
                </Pressable>
                <Pressable
                    testID="admin-pipeline-clear-all"
                    variant="outline"
                    disabled={selectedCount === 0}
                    onPress={() => changeSelection([], downloadMissingAssets)}
                >
                    <Text className={labelText}>Clear all</Text>
                </Pressable>
            </View>
            <View className="mt-2">
                {STAGES.map((stage) => (
                    <CheckRow
                        key={stage.key}
                        testID={`admin-pipeline-stage-${stage.key}`}
                        label={stage.label}
                        subtext={stage.subtext}
                        checked={selectedStages.includes(stage.key)}
                        onPress={() => toggleStage(stage.key)}
                    />
                ))}
            </View>
            {preview?.confirmation_required ? (
                <View testID="admin-pipeline-auto-include" className="mt-3">
                    <Text className={labelText}>Also required</Text>
                    <Text className={mutedText}>
                        These stages will run automatically because your selection depends on them:
                    </Text>
                    <Text testID="admin-pipeline-auto-included" className={labelText}>
                        {preview.stages_auto_included.map(stageName).join(", ")}
                    </Text>
                    {reducedAutoIncluded.length > 0 ? (
                        <Text testID="admin-pipeline-auto-include-reduced-note" className={`mt-2 ${mutedText}`}>
                            {reducedAutoIncluded.map(stageName).join(", ")}{" "}
                            {reducedAutoIncluded.length === 1 ? "runs" : "run"} in reduced form — only filling in what
                            is missing, never redoing work already done.
                            {reducedAutoIncluded.includes("fetch-bills")
                                ? " Fetch bills will not look for new bills in Legistar. It asks for a bill in this run by name only when that bill has nothing saved yet."
                                : ""}{" "}
                            Tick a stage yourself to run it in full.
                        </Text>
                    ) : null}
                </View>
            ) : null}
            {!downloadMissingAssets && prereqViolations.length > 0 ? (
                <View testID="admin-pipeline-prereq-warning" className="mt-3">
                    <Text className={errorText}>Bills will fail without their prerequisites</Text>
                    {prereqViolations.map((v, i) => (
                        <Text key={`${v.stage}-${v.prerequisite}-${i}`} className={mutedText}>
                            {`${v.bill_count} bills will FAIL ${stageName(v.stage)} because they have no ${v.missing_artifact} — enable Download missing assets or check ${stageName(v.prerequisite)}`}
                        </Text>
                    ))}
                </View>
            ) : null}
            <View className="mt-3">
                <CheckRow
                    testID="admin-pipeline-download-missing-assets"
                    label="Download missing assets"
                    subtext={
                        bothFetchesSelected
                            ? "Both fetch stages are checked — there is nothing to backfill."
                            : "Auto-runs upstream stages for any bills missing required data. Off = run only the checked stages; bills missing prerequisites will fail."
                    }
                    checked={bothFetchesSelected || downloadMissingAssets}
                    disabled={bothFetchesSelected}
                    onPress={() => changeSelection(selectedStages, !downloadMissingAssets)}
                />
            </View>
            {pipelineError ? (
                <Text testID="admin-pipeline-error" className={`mt-3 ${errorText}`}>
                    {pipelineError}
                </Text>
            ) : null}
            {queued ? (
                <Text testID="admin-pipeline-queued" className={`mt-3 ${labelText}`}>
                    Pipeline run queued.
                </Text>
            ) : null}
            <Pressable
                testID="admin-pipeline-run"
                variant="default"
                className="mt-3"
                disabled={!hasSelection || loading}
                onPress={() => void startRun()}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    Run pipeline for {billId === null ? "all bills" : `bill ${billExternalId ?? ""}`} in{" "}
                    {titleize(locale?.city ?? "")}
                </Text>
            </Pressable>
            {hasSelection ? null : <Text className={`mt-1 ${mutedText}`}>Pick at least one stage to run.</Text>}
        </View>
    );
}
