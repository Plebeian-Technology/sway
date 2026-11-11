import { usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { WifiOff } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import type { PipelineRunSubscriptionState } from "app/frontend/hooks/usePipelineRunSubscription";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import ForceFailDialog from "app/frontend/components/admin/creator/ForceFailDialog";
import { isInFlightRunStatus } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { failedStageInfo } from "app/frontend/components/admin/creator/pipeline-controls/failedStageInfo";
import { pickedBillIdFor } from "app/frontend/components/admin/creator/pipeline-controls/pickedBillId";
import { usePipelineControlsState } from "app/frontend/components/admin/creator/pipeline-controls/usePipelineControlsState";
import { usePipelineRunActions } from "app/frontend/components/admin/creator/pipeline-controls/usePipelineRunActions";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import type { IPageProps } from "app/frontend/components/admin/creator/pipeline-controls/types";
import PipelineFailureHeader from "app/frontend/components/admin/creator/pipeline-controls/PipelineFailureHeader";
import PipelineResumeActions from "app/frontend/components/admin/creator/pipeline-controls/PipelineResumeActions";
import PipelineStageSelector from "app/frontend/components/admin/creator/pipeline-controls/PipelineStageSelector";
import PipelineActionButtons from "app/frontend/components/admin/creator/pipeline-controls/PipelineActionButtons";

interface IControlsProps {
    // @lat: [[bill-creator-pipeline-controls-panel#Why subscriptionState is threaded down as a prop]]
    subscriptionState: PipelineRunSubscriptionState;
}

const BillCreatorPipelineControls: React.FC<IControlsProps> = ({ subscriptionState }) => {
    const { props } = usePage<IPageProps>();
    const [swayLocale] = useSwayLocale();
    const run = props.legislation_pipeline_run ?? null;
    const status = run?.status ?? null;
    const bill = props.bill;
    const billId = bill?.id ?? null;
    const errors = (props.errors ?? {}) as Record<string, string | undefined>;
    const staleCount = props.stale_pipeline_run_count ?? 0;
    const orphanCount = props.orphan_pipeline_run_count ?? 0;
    const pipelinePreview = props.pipeline_preview ?? null;
    const { downgraded } = subscriptionState;

    const activeLocaleId =
        swayLocale?.id ??
        (props.sway_locale as { id?: number } | undefined)?.id ??
        (props.bill as { sway_locale_id?: number } | undefined)?.sway_locale_id ??
        (typeof window !== "undefined"
            ? Number(new URLSearchParams(window.location.search).get("sway_locale_id")) || undefined
            : undefined);

    const { selectedStages, downloadMissingAssets, setSelectedStages, setDownloadMissingAssets } =
        usePipelineControlsState();

    // @lat: [[bill-creator-pipeline-controls-panel#Why pickedBillId falls back to "run every bill"]]
    const pickedBillId = pickedBillIdFor(billId);

    const [forceFailOpen, setForceFailOpen] = useState<boolean>(false);
    const confirm = useConfirm();

    const { isPosting, handleResume, handleRestart, handleRun, handleSweepStale, handleDeleteOrphans } =
        usePipelineRunActions({
            run,
            selectedStages,
            pickedBillId,
            swayLocaleId: activeLocaleId,
            downloadMissingAssets,
            staleCount,
            orphanCount,
            confirm,
        });

    // @lat: [[bill-creator-pipeline-controls-panel#Why isRunning checks every non-finished status, not just queued/running]]
    const isRunning = isInFlightRunStatus(status);
    const hasSelection = selectedStages.length > 0;
    const runDisabled = isRunning || !hasSelection;

    // @lat: [[bill-creator-pipeline-controls-panel#Why runDisabledReason is a named string, not a title on a wrapper div]]
    const runDisabledReason = isRunning
        ? "A run is in flight. Cancel it before starting another."
        : hasSelection
          ? null
          : "Pick at least one stage to run.";

    const { failedStageNumber, failedStageDisplay, parentShortId } = failedStageInfo(run);

    const handleToggleStage = useCallback(
        (key: string) => {
            const next = selectedStages.includes(key)
                ? selectedStages.filter((s) => s !== key)
                : [...selectedStages, key];
            setSelectedStages(next);
        },
        [selectedStages, setSelectedStages],
    );

    const showFailureHeader = run?.status === "failed" && run?.kind === "single";
    const showStandaloneOriginHint =
        run?.status !== "failed" && (run?.origin === "resume" || run?.origin === "restart") && Boolean(parentShortId);

    return (
        <div data-testid="pipeline-controls" className="flex flex-col gap-4" aria-busy={isRunning || undefined}>
            {showFailureHeader && run && (
                <PipelineFailureHeader
                    run={run}
                    failedStageNumber={failedStageNumber}
                    failedStageDisplay={failedStageDisplay}
                    parentShortId={parentShortId}
                />
            )}

            {showFailureHeader && (
                <PipelineResumeActions
                    failedStageNumber={failedStageNumber}
                    isPosting={isPosting}
                    onResume={handleResume}
                    onRestart={handleRestart}
                />
            )}

            {run && isRunning && (
                <div className="flex flex-wrap items-center gap-3" data-testid="pipeline-inflight-actions">
                    <span className="inline-flex items-center gap-1.5">
                        <Button
                            type="button"
                            variant="destructive"
                            size="sm"
                            onClick={() => setForceFailOpen(true)}
                            disabled={isPosting}
                            data-testid="btn-force-fail"
                            className="min-h-[44px]"
                        >
                            Force fail
                        </Button>
                        <FeatureInfo note="pipeline.forceFail" />
                    </span>
                </div>
            )}

            {showStandaloneOriginHint && run && (
                <p className="text-xs text-muted-foreground" data-testid="pipeline-origin-hint">
                    {run.origin === "resume" ? "Resume" : "Restart"} of run {parentShortId}
                </p>
            )}

            {/* @lat: [[bill-creator-pipeline-controls-panel#Why ForceFailDialog stays mounted when closed]] */}
            {run && <ForceFailDialog runId={run.id} open={forceFailOpen} onOpenChange={setForceFailOpen} />}

            {errors.pipeline && (
                <Alert data-testid="pipeline-conflict-alert" variant="destructive">
                    <AlertTitle>Pipeline already running</AlertTitle>
                    <AlertDescription>
                        {/* @lat: [[bill-creator-pipeline-controls-panel#Why the pipeline-conflict alert avoids saying "the panel above"]] */}
                        A pipeline run is already in progress. Clear any pinned run to see it.
                    </AlertDescription>
                </Alert>
            )}

            {/* @lat: [[bill-creator-pipeline-controls-panel#Why the cable-downgrade banner needs its own isRunning gate]] */}
            {downgraded &&
                isRunning && (
                    // @lat: [[bill-creator-pipeline-controls-panel#Why the cable-downgrade banner overrides Alert's role to "status"]]
                    // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role
                    <Alert variant="warning" role="status" aria-live="polite" data-testid="cable-downgrade-banner">
                        <WifiOff className="h-4 w-4" />
                        <AlertDescription>Live updates paused — polling every 5s. Reconnecting…</AlertDescription>
                    </Alert>
                )}

            {/* @lat: [[bill-creator-pipeline-controls-panel#Why PipelineStageSelector gets a whole-list setter, not per-toggle calls]] */}
            <PipelineStageSelector
                selectedStages={selectedStages}
                isRunning={isRunning}
                pipelinePreview={pipelinePreview}
                downloadMissingAssets={downloadMissingAssets}
                onToggleStage={handleToggleStage}
                onSetStages={setSelectedStages}
                onDownloadMissingAssetsChange={setDownloadMissingAssets}
            />

            <PipelineActionButtons
                runDisabled={runDisabled}
                runDisabledReason={runDisabledReason}
                isRunning={isRunning}
                pickedBillId={pickedBillId}
                billExternalId={bill?.external_id}
                staleCount={staleCount}
                orphanCount={orphanCount}
                onRun={handleRun}
                onSweepStale={handleSweepStale}
                onDeleteOrphans={handleDeleteOrphans}
            />
        </div>
    );
};

export default BillCreatorPipelineControls;
