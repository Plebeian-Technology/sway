import { Fragment } from "react";
import { Info, TriangleAlert } from "lucide-react";
import { cn } from "app/frontend/lib/utils";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Checkbox } from "app/frontend/components/ui/checkbox";
import { Label } from "app/frontend/components/ui/label";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import {
    REDUCED_WHEN_AUTO_INCLUDED,
    STAGES,
    STAGE_DISPLAY_NAMES,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";
import type { IPipelinePreview } from "app/frontend/components/admin/creator/pipeline-controls/types";

interface IPipelineStageSelectorProps {
    selectedStages: string[];
    isRunning: boolean;
    pipelinePreview: IPipelinePreview | null;
    downloadMissingAssets: boolean;
    onToggleStage: (key: string) => void;
    // @lat: [[pipeline-stage-auto-include-reduced-work#Why the stage-selection buttons are Select all / Clear all, not one tick-all box]]
    onSetStages: (next: string[]) => void;
    onDownloadMissingAssetsChange: (next: boolean) => void;
}

const ALL_STAGE_KEYS: string[] = STAGES.map((s) => s.key);

// @lat: [[pipeline-stage-auto-include-reduced-work#Why "Download missing assets" is disabled when both fetch stages are checked]]
const PipelineStageSelector: React.FC<IPipelineStageSelectorProps> = ({
    selectedStages,
    isRunning,
    pipelinePreview,
    downloadMissingAssets,
    onToggleStage,
    onSetStages,
    onDownloadMissingAssetsChange,
}) => {
    // @lat: [[pipeline-stage-auto-include-reduced-work#Why the "Stages to run" card's selected count is derived from STAGES, not selectedStages.length]]
    const selectedCount = STAGES.filter((s) => selectedStages.includes(s.key)).length;
    const allSelected = selectedCount === STAGES.length;
    const noneSelected = selectedCount === 0;
    // @lat: [[pipeline-stage-auto-include-reduced-work#Why "Download missing assets" is disabled when both fetch stages are checked]]
    const dmaDisabledByBothFetches =
        selectedStages.includes("fetch-bills") && selectedStages.includes("fetch-hearings");
    const dmaDisabled = isRunning || dmaDisabledByBothFetches;
    // @lat: [[pipeline-stage-auto-include-reduced-work#PipelineStageSelector notes]]
    const dmaVisibleChecked = dmaDisabledByBothFetches ? true : downloadMissingAssets;

    // @lat: [[pipeline-stage-auto-include-reduced-work#Why the auto-included stage chips are comma-separated with a screen-reader-only comma]]
    const reducedAutoIncluded = (pipelinePreview?.stages_auto_included ?? []).filter((stage) =>
        (REDUCED_WHEN_AUTO_INCLUDED as readonly string[]).includes(stage),
    );

    const prereqViolations = pipelinePreview?.prereq_violations ?? [];
    const showWarnAlert = !downloadMissingAssets && prereqViolations.length > 0 && !isRunning;

    return (
        <div className="flex flex-col gap-2 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo">
            <div className={cn("flex flex-wrap items-center justify-between gap-2", isRunning && "opacity-60")}>
                <div className="flex items-center gap-1.5">
                    <span className="text-xs font-semibold uppercase tracking-widest">Stages to run</span>
                    <FeatureInfo note="pipeline.stageSelector" />
                </div>
                {/* @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box]] */}
                <div className="flex flex-wrap items-center gap-2">
                    <span className="text-xs tabular-nums text-muted-foreground" data-testid="stage-selection-count">
                        {selectedCount} of {STAGES.length} selected
                    </span>
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        data-testid="select-all-stages"
                        disabled={allSelected}
                        onClick={() => onSetStages(ALL_STAGE_KEYS)}
                        className="min-h-[44px] sm:min-h-0"
                    >
                        Select all
                    </Button>
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        data-testid="clear-all-stages"
                        disabled={noneSelected}
                        onClick={() => onSetStages([])}
                        className="min-h-[44px] sm:min-h-0"
                    >
                        Clear all
                    </Button>
                </div>
            </div>
            <div className="border-b-neo border-border-soft" />
            <ul className="flex flex-col gap-2 pt-2" aria-busy={isRunning || undefined}>
                {STAGES.map((s) => {
                    const id = `stage-${s.key}`;
                    return (
                        <li
                            key={s.key}
                            className={cn("flex items-center gap-3 min-h-[44px] py-1.5", isRunning && "opacity-60")}
                        >
                            <Checkbox
                                id={id}
                                data-testid={`checkbox-stage-${s.key}`}
                                checked={selectedStages.includes(s.key)}
                                onCheckedChange={() => onToggleStage(s.key)}
                            />
                            <Label
                                htmlFor={id}
                                className="cursor-pointer flex flex-col items-start gap-0.5 flex-1 min-w-0 py-0.5"
                            >
                                <span className="font-semibold text-sm">{s.label}</span>
                                <span className="block text-xs text-muted-foreground break-words">{s.subtext}</span>
                            </Label>
                        </li>
                    );
                })}
            </ul>
            {pipelinePreview?.confirmation_required && (
                <Alert data-testid="pipeline-auto-include-alert" variant="default" className="mt-3">
                    <Info className="h-4 w-4" />
                    <AlertTitle>Also required</AlertTitle>
                    <AlertDescription>
                        These stages will run automatically because your selection depends on them:
                        {/* @lat: [[pipeline-stage-auto-include-reduced-work#Why the auto-included stage chips are comma-separated with a screen-reader-only comma]] */}
                        <div className="mt-2 flex flex-wrap gap-2">
                            {pipelinePreview.stages_auto_included.map((stage, i) => (
                                <Fragment key={stage}>
                                    {i > 0 && <span className="sr-only">, </span>}
                                    <Badge variant="stamp" tone="info">
                                        {STAGE_DISPLAY_NAMES[stage] ?? stage}
                                    </Badge>
                                </Fragment>
                            ))}
                        </div>
                        {/* @lat: [[pipeline-stage-auto-include-reduced-work#PipelineStageSelector notes]] */}
                        {reducedAutoIncluded.length > 0 && (
                            <p className="mt-2 text-xs" data-testid="pipeline-auto-include-reduced-note">
                                {reducedAutoIncluded.map((s) => STAGE_DISPLAY_NAMES[s] ?? s).join(", ")}{" "}
                                {reducedAutoIncluded.length === 1 ? "runs" : "run"} in reduced form — only filling in
                                what is missing, never redoing work already done.
                                {reducedAutoIncluded.includes("fetch-bills") &&
                                    " Fetch bills will not look for new bills in Legistar. It asks for a bill in this run by name only when that bill has nothing saved yet."}{" "}
                                Tick a stage yourself to run it in full.
                            </p>
                        )}
                    </AlertDescription>
                </Alert>
            )}
            {/* @lat: [[pipeline-stage-auto-include-reduced-work#Why the prerequisite-violation warning renders before the run starts]] */}
            {showWarnAlert && (
                <Alert data-testid="pipeline-prereq-warn-alert" variant="warning" className="mt-3">
                    <TriangleAlert className="h-4 w-4" />
                    <div className="col-start-2 flex items-center gap-1.5">
                        <AlertTitle className="min-w-0">Bills will fail without their prerequisites</AlertTitle>
                        <FeatureInfo note="pipeline.prerequisiteWarning" className="shrink-0" />
                    </div>
                    <AlertDescription>
                        <ul className="mt-1 flex flex-col gap-1">
                            {prereqViolations.map((v, i) => {
                                const stageLabel = STAGE_DISPLAY_NAMES[v.stage] ?? v.stage;
                                const prereqLabel = STAGE_DISPLAY_NAMES[v.prerequisite] ?? v.prerequisite;
                                return (
                                    <li
                                        key={`${v.stage}-${v.prerequisite}-${i}`}
                                        data-testid={`pipeline-prereq-violation-${v.stage}`}
                                    >
                                        {v.bill_count} bills will FAIL {stageLabel} because they have no{" "}
                                        {v.missing_artifact} — enable Download missing assets or check {prereqLabel}
                                    </li>
                                );
                            })}
                        </ul>
                    </AlertDescription>
                </Alert>
            )}
            <div className="border-b-neo border-border-soft" />
            <div className="flex items-start gap-3 min-h-[44px] py-1.5 pt-2">
                <Checkbox
                    id="download-missing-assets"
                    data-testid="checkbox-download-missing-assets"
                    checked={dmaVisibleChecked}
                    onCheckedChange={(v) => onDownloadMissingAssetsChange(v === true)}
                    disabled={dmaDisabled}
                />
                <Label
                    htmlFor="download-missing-assets"
                    className="cursor-pointer flex flex-col items-start gap-0.5 flex-1 min-w-0 py-0.5"
                >
                    <span className="font-semibold">Download missing assets</span>
                    <span className="block text-xs text-muted-foreground break-words">
                        {dmaDisabledByBothFetches
                            ? "Both fetch stages are checked — there is nothing to backfill."
                            : "Auto-runs upstream stages for any bills missing required data. Off = run only the checked stages; bills missing prerequisites will fail."}
                    </span>
                </Label>
            </div>
        </div>
    );
};

export default PipelineStageSelector;
