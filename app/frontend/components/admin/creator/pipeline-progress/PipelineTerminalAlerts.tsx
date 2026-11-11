import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Badge } from "app/frontend/components/ui/badge";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";
import { PHASE_LABELS } from "app/frontend/components/admin/creator/pipeline-progress/constants";
import { exactTime, failureTiming } from "app/frontend/sway_utils/failureTiming";

interface IProps {
    run: ILegislationPipelineRun;
    processed: number;
    total: number | null;
    phase: ILegislationPipelineRun["phase"];
    // @lat: [[pipeline-terminal-alert-remedy-wording#Why the remedy no longer says the button retries the whole run]]
    pickedBillId: string;
}

const PipelineTerminalAlerts: React.FC<IProps> = ({ run, processed, total, phase, pickedBillId }) => {
    const { status } = run;

    // @lat: [[pipeline-terminal-alert-remedy-wording#Why the "succeeded" stage chip does not say "cached"]]
    const stages = run.pipeline_run_stages ?? [];
    const showCachedChips = run.status === "failed" && run.kind === "single";
    const failureTimingText = failureTiming(run.completed_at);
    const cancelledAt = exactTime(run.completed_at);

    return (
        <>
            {status === "completed" && (
                <Alert data-testid="pipeline-success-alert" variant="success">
                    <AlertTitle>Pipeline complete</AlertTitle>
                    <AlertDescription>
                        <span className="tabular-nums lining-nums">{run.bills_updated ?? 0}</span> bill(s) updated.
                    </AlertDescription>
                </Alert>
            )}

            {status === "succeeded" && (
                <Alert data-testid="pipeline-succeeded-alert" variant="success">
                    <AlertTitle>Run succeeded</AlertTitle>
                    <AlertDescription>All bills processed successfully.</AlertDescription>
                </Alert>
            )}

            {status === "partial" && (
                <Alert data-testid="pipeline-partial-alert" variant="warning">
                    <AlertTitle>Run completed with failures</AlertTitle>
                    <AlertDescription>Some bills failed. See the summary above for details.</AlertDescription>
                </Alert>
            )}

            {showCachedChips && stages.length > 0 && (
                <div className="flex items-start gap-1.5">
                    <ul data-testid="pipeline-cached-stages" className="flex flex-col gap-1 text-xs">
                        {stages.map((stage) => {
                            const stageFinishedAt = exactTime(stage.finished_at);

                            return (
                                <li key={`${stage.position}-${stage.stage_name}`} className="flex items-center gap-2">
                                    <span className="tabular-nums lining-nums text-muted-foreground">
                                        {stage.position}.
                                    </span>
                                    <span className="font-semibold">{stage.stage_name}</span>
                                    {stage.status === "succeeded" && (
                                        // @lat: [[pipeline-terminal-alert-remedy-wording#Why the "succeeded" stage chip does not say "cached"]]
                                        <Badge variant="stamp" tone="neutral" aria-label="Stage already succeeded">
                                            succeeded
                                        </Badge>
                                    )}
                                    {stage.status === "failed" && (
                                        <Badge variant="stamp" tone="danger">
                                            failed
                                        </Badge>
                                    )}
                                    {stage.status === "failed" && stageFinishedAt && (
                                        <span
                                            data-testid="pipeline-stage-finished-at"
                                            className="text-xs text-muted-foreground tabular-nums lining-nums"
                                        >
                                            {stageFinishedAt}
                                        </span>
                                    )}
                                </li>
                            );
                        })}
                    </ul>
                    <FeatureInfo note="pipeline.cachedStages" />
                </div>
            )}

            {status === "failed" && (
                <Alert data-testid="pipeline-error-alert" variant="destructive">
                    <AlertTitle>Pipeline failed</AlertTitle>
                    {/* @lat: [[pipeline-terminal-alert-remedy-wording#Why the remedy names Resume/Restart only on a failed single-bill run]] */}
                    <AlertDescription>
                        {phase ? `During ${PHASE_LABELS[phase] ?? phase}: ` : ""}
                        {run.error_message ?? "Unknown error"} —{" "}
                        {showCachedChips
                            ? "use Resume above to try the failed stage again, or Restart to run it from the beginning."
                            : pickedBillId
                              ? "the bill picker above holds one bill, so Run pipeline starts a run for that bill alone."
                              : "pick the stages above and click Run pipeline, which starts a run over every bill."}
                        {failureTimingText && (
                            <p data-testid="pipeline-failure-timing" className="text-sm tabular-nums lining-nums">
                                {failureTimingText}
                            </p>
                        )}
                    </AlertDescription>
                </Alert>
            )}

            {status === "cancelled" && (
                <Alert data-testid="pipeline-cancelled-alert" variant="warning">
                    <AlertTitle>Run cancelled</AlertTitle>
                    <AlertDescription>
                        {cancelledAt && (
                            <>
                                Cancelled at <span className="tabular-nums lining-nums">{cancelledAt}</span>.{" "}
                            </>
                        )}
                        <span className="tabular-nums lining-nums">{processed}</span> of{" "}
                        <span className="tabular-nums lining-nums">{total ?? "?"}</span> bills processed before cancel.
                    </AlertDescription>
                </Alert>
            )}
        </>
    );
};

export default PipelineTerminalAlerts;
