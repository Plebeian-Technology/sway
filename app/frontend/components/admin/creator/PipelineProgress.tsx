import { useCallback } from "react";
import { useTwoTapConfirm } from "app/frontend/hooks/useTwoTapConfirm";
import {
    usePipelineRunSubscription,
    type PipelineRunSubscriptionState,
} from "app/frontend/hooks/usePipelineRunSubscription";
import { Button } from "app/frontend/components/ui/button";
import { Progress } from "app/frontend/components/ui/progress";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";
import {
    isInFlightRunStatus,
    PHASE_52_NON_TERMINAL_STATUSES,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { PHASE_LABELS } from "app/frontend/components/admin/creator/pipeline-progress/constants";
import PipelineProgressHeader from "app/frontend/components/admin/creator/pipeline-progress/PipelineProgressHeader";
import PipelineRunningDetail from "app/frontend/components/admin/creator/pipeline-progress/PipelineRunningDetail";
import PipelineErrorsAccordion from "app/frontend/components/admin/creator/pipeline-progress/PipelineErrorsAccordion";
import PipelineTerminalAlerts from "app/frontend/components/admin/creator/pipeline-progress/PipelineTerminalAlerts";

interface IProps {
    run: ILegislationPipelineRun | null;
    // @lat: [[pipeline-progress-panel#Why pickedBillId is threaded through to PipelineTerminalAlerts]]
    pickedBillId: string;
    // @lat: [[pipeline-progress-panel#Why subscription is optional, with a fallback connection]]
    subscription?: PipelineRunSubscriptionState;
    // @lat: [[pipeline-progress-panel#Why onCancelRun is required, not optional]]
    onCancelRun: (runId: number) => void;
}

// @lat: [[pipeline-progress-panel#Why the panel updates via PipelineRunChannel, and how cancel works]]
const PipelineProgress: React.FC<IProps> = ({ run, pickedBillId, subscription, onCancelRun }) => {
    // @lat: [[pipeline-progress-panel#Why subscription is optional, with a fallback connection]]
    const fallback = usePipelineRunSubscription(subscription === undefined ? (run?.remote_run_id ?? null) : null, [
        "legislation_pipeline_run",
    ]);
    const { connected: isSubscribed } = subscription ?? fallback;
    const { confirming, arm, disarm } = useTwoTapConfirm();

    const handleCancelClick = useCallback(() => {
        if (!run) return;
        if (confirming) {
            disarm();
            onCancelRun(run.id);
            return;
        }
        arm();
    }, [confirming, run, arm, disarm, onCancelRun]);

    if (!run) {
        return (
            <div
                data-testid="pipeline-progress"
                className="rounded-xl border-neo border-border-soft bg-card p-4 text-sm italic text-muted-foreground"
            >
                No pipeline run yet. Select stages and click <span className="font-semibold">Run pipeline</span> to
                start ingestion.
            </div>
        );
    }

    // @lat: [[pipeline-progress-panel#Why the destructured run fields all have defaults]]
    const {
        status,
        processed = 0,
        total = null,
        phase = null,
        current_bill_external_id = null,
        eta_seconds = null,
        errors = [],
        queued = [],
    } = run;
    const pct = total && total > 0 ? (processed / total) * 100 : 0;
    const phaseLabel = phase ? (PHASE_LABELS[phase] ?? phase) : null;
    // @lat: [[pipeline-progress-panel#Why isInFlight uses an allow-list]]
    const isInFlight = isInFlightRunStatus(status);
    // @lat: [[pipeline-progress-panel#Why cancellable checks the shared non-terminal list]]
    const cancellable = status !== null && (PHASE_52_NON_TERMINAL_STATUSES as readonly string[]).includes(status);
    // @lat: [[pipeline-progress-panel#Why isAbandoned is kept in step with RunConflictBanner]]
    const isAbandoned = run.abandoned === true;

    return (
        <div
            data-testid="pipeline-progress"
            className="flex flex-col gap-4 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo"
        >
            <PipelineProgressHeader status={status} errorCount={errors.length} phaseLabel={phaseLabel} />

            {isAbandoned && (
                <div className="flex items-start gap-1.5">
                    <p data-testid="pipeline-abandoned-notice" className="text-sm text-muted-foreground">
                        Nothing is working on this run — no worker is carrying it, and nothing has written to it for
                        hours. Clearing it frees the Run button. Resume then starts again at the stage it stopped in.
                    </p>
                    <FeatureInfo note="pipeline.abandonedNotice" />
                </div>
            )}

            {/* @lat: [[pipeline-progress-panel#Why the progress bar only shows while in flight and not abandoned]] */}
            {isInFlight && !isAbandoned && <Progress value={pct} data-testid="pipeline-progress-bar" />}

            {status === "running" && (
                <PipelineRunningDetail
                    processed={processed}
                    total={total}
                    currentBillExternalId={current_bill_external_id}
                    etaSeconds={eta_seconds}
                    queued={queued}
                />
            )}

            {errors.length > 0 && <PipelineErrorsAccordion errors={errors} status={status} />}

            <PipelineTerminalAlerts
                run={run}
                processed={processed}
                total={total}
                phase={phase}
                pickedBillId={pickedBillId}
            />

            <div className="flex flex-wrap items-center gap-3">
                {cancellable && (
                    <span className="inline-flex items-center gap-1.5">
                        <Button
                            type="button"
                            size="sm"
                            variant={confirming ? "destructive" : "outline"}
                            onClick={handleCancelClick}
                            data-testid="btn-cancel-pipeline"
                            className="min-h-[44px]"
                        >
                            {/* @lat: [[pipeline-progress-panel#Why the Cancel button reuses the same endpoint for a live run and an abandoned one]] */}
                            {confirming
                                ? isAbandoned
                                    ? "Tap again to clear"
                                    : "Tap again to cancel"
                                : isAbandoned
                                  ? "Clear this run"
                                  : "Cancel run"}
                        </Button>
                        <FeatureInfo note="pipeline.cancelRunProgress" />
                    </span>
                )}
                {!isSubscribed && isInFlight && (
                    <span className="text-xs italic text-muted-foreground">
                        Live updates paused — refreshing on poll.
                    </span>
                )}
            </div>
        </div>
    );
};

export default PipelineProgress;
