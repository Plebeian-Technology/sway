import { usePage } from "@inertiajs/react";
import { useCallback } from "react";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import { useTwoTapConfirm } from "app/frontend/hooks/useTwoTapConfirm";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import {
    isTerminalRunStatus,
    type TPipelineRunStatus,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";

interface ILegislationPipelineRun {
    id: number;
    status: TPipelineRunStatus | null;
    started_at: string | null;
    // @lat: [[run-conflict-banner#Why current_stage is not on ILegislationPipelineRun here]]
    // @lat: [[run-conflict-banner#Why bill_external_id is read off the linked Bill]]
    bill_external_id: string | null;
    // @lat: [[run-conflict-banner#Why abandoned defaults to "attended" when absent]]
    abandoned?: boolean | null;
    // @lat: [[run-conflict-banner#Why there is no cancelled_at field here]]
}

interface IPageProps {
    active_legislation_pipeline_run?: ILegislationPipelineRun | null;
    [key: string]: unknown;
}

interface IProps {
    // @lat: [[run-conflict-banner#Why onCancelRun's cancel-safety lives in BillCreatorShell]]
    onCancelRun: (runId: number) => void;
}

// @lat: [[run-conflict-banner#Why the banner reads active_legislation_pipeline_run, not the pinned run]]
const RunConflictBanner: React.FC<IProps> = ({ onCancelRun }) => {
    const { props } = usePage<IPageProps>();
    const run = props.active_legislation_pipeline_run ?? null;
    const { confirming, arm, disarm } = useTwoTapConfirm();

    const handleCancel = useCallback(() => {
        if (!run) return;
        if (confirming) {
            disarm();
            onCancelRun(run.id);
            return;
        }
        arm();
    }, [confirming, run, arm, disarm, onCancelRun]);

    if (!run || isTerminalRunStatus(run.status)) return null;

    const wallClock =
        run.started_at !== null
            ? new Date(run.started_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
            : null;

    // @lat: [[run-conflict-banner#Why isQueued treats a null status as queued, not "in progress"]]
    const isQueued = run.status === "queued" || run.status === null;

    // @lat: [[run-conflict-banner#Why isAbandoned is checked before isQueued]]
    const isAbandoned = run.abandoned === true;

    // @lat: [[run-conflict-banner#Why billLabel/description avoid promising a wait time]]
    const billLabel = run.bill_external_id;
    const runLabel = `Pipeline run ${run.id}${billLabel ? ` (bill ${billLabel})` : " (all bills)"}`;
    let description: string;
    if (isAbandoned) {
        // @lat: [[run-conflict-banner#Why billLabel/description avoid promising a wait time]]
        description = `${runLabel} stopped${wallClock ? `, started ${wallClock},` : ""} and nothing is working on it now. It is holding the Run button off. Clearing it frees that button and leaves the run resumable.`;
    } else if (isQueued) {
        description = `Pipeline run ${run.id} is queued. It starts when a worker picks it up.`;
    } else {
        description = `${runLabel} is in progress${wallClock ? ` — started ${wallClock}` : ""}. Cancel to start a new run.`;
    }

    return (
        <Alert variant="warning" data-testid="run-conflict-banner">
            {/* @lat: [[run-conflict-banner#Why the AlertTitle must stay tied to the same branch as the description]] */}
            <AlertTitle>
                {isAbandoned
                    ? "Pipeline run left unfinished"
                    : isQueued
                      ? "Pipeline run queued"
                      : "Pipeline run in progress"}
            </AlertTitle>
            <AlertDescription>
                <span className="tabular-nums lining-nums">{description}</span>
                <div className="flex items-center gap-2 pt-2">
                    <Button
                        type="button"
                        size="sm"
                        variant={confirming ? "destructive" : "outline"}
                        onClick={handleCancel}
                        data-testid="btn-banner-cancel"
                    >
                        {/* @lat: [[run-conflict-banner#Why the Cancel button reuses the same endpoint for a live run and an abandoned one]] */}
                        {confirming
                            ? isAbandoned
                                ? "Tap again to clear"
                                : "Tap again to cancel"
                            : isAbandoned
                              ? "Clear this run"
                              : "Cancel run"}
                    </Button>
                    <FeatureInfo note="creator.cancelRun" />
                </div>
            </AlertDescription>
        </Alert>
    );
};

export default RunConflictBanner;
