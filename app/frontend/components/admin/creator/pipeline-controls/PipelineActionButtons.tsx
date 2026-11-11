import { LoaderCircle } from "lucide-react";
import { Button } from "app/frontend/components/ui/button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";
import { titleize } from "app/frontend/sway_utils";

// @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why runDisabledReason is a named string, not a title on a wrapper div#RUN_DISABLED_NOTICE_ID ties the notice to the button]]
const RUN_DISABLED_NOTICE_ID = "run-pipeline-disabled-reason";

interface IPipelineActionButtonsProps {
    runDisabled: boolean;
    // @lat: [[bill-creator-pipeline-controls-panel#BillCreatorPipelineControls mechanics#Why runDisabledReason is a named string, not a title on a wrapper div#The runDisabledReason prop carries the words, not a boolean]]
    runDisabledReason: string | null;
    isRunning: boolean;
    pickedBillId: string;
    billExternalId?: string;
    staleCount: number;
    orphanCount: number;
    onRun: () => void;
    onSweepStale: () => void;
    onDeleteOrphans: () => void;
}

const PipelineActionButtons: React.FC<IPipelineActionButtonsProps> = ({
    runDisabled,
    runDisabledReason,
    isRunning,
    pickedBillId,
    billExternalId,
    staleCount,
    orphanCount,
    onRun,
    onSweepStale,
    onDeleteOrphans,
}) => {
    const [swayLocale] = useSwayLocale();
    return (
        <div className="flex flex-col gap-2">
            <div className="flex flex-wrap gap-3">
                <span className="inline-flex w-full items-center gap-2 sm:w-auto">
                    <Button
                        type="button"
                        variant="default"
                        onClick={onRun}
                        disabled={runDisabled}
                        aria-describedby={runDisabledReason ? RUN_DISABLED_NOTICE_ID : undefined}
                        data-testid="btn-run-pipeline"
                        className="h-auto min-h-[44px] min-w-0 w-full shrink whitespace-normal wrap-break-word py-2.5 sm:w-auto"
                    >
                        Run pipeline for {pickedBillId ? `bill ${billExternalId}` : "all bills"} in{" "}
                        {titleize(swayLocale?.city ?? "")}
                    </Button>
                    {isRunning && (
                        <LoaderCircle
                            className="size-4 animate-spin text-muted-foreground"
                            aria-label="Pipeline run in progress"
                            data-testid="pipeline-run-spinner"
                        />
                    )}
                </span>
                <TooltipProvider delayDuration={150}>
                    {staleCount > 0 && (
                        <span className="inline-flex w-full items-center gap-1.5 sm:w-auto">
                            <Tooltip>
                                <TooltipTrigger asChild>
                                    <Button
                                        type="button"
                                        variant="destructive"
                                        onClick={onSweepStale}
                                        data-testid="btn-sweep-stale-pipeline-runs"
                                        className="min-h-[44px] w-full sm:w-auto"
                                    >
                                        Remove {staleCount} stuck run{staleCount === 1 ? "" : "s"}
                                    </Button>
                                </TooltipTrigger>
                                <TooltipContent className="max-w-xs">
                                    Marks unfinished runs as failed only after 4 hours without updates and with no
                                    background job or live summary batch. Run history is kept.
                                </TooltipContent>
                            </Tooltip>
                            <FeatureInfo note="pipeline.sweepStale" />
                        </span>
                    )}
                    {orphanCount > 0 && (
                        <span className="inline-flex w-full items-center gap-1.5 sm:w-auto">
                            <Tooltip>
                                <TooltipTrigger asChild>
                                    <Button
                                        type="button"
                                        variant="destructive"
                                        onClick={onDeleteOrphans}
                                        data-testid="btn-delete-orphan-pipeline-runs"
                                        className="min-h-[44px] w-full sm:w-auto"
                                    >
                                        Delete {orphanCount} orphan run{orphanCount === 1 ? "" : "s"}
                                    </Button>
                                </TooltipTrigger>
                                <TooltipContent className="max-w-xs">
                                    Permanently deletes runs queued or running for over 4 hours with no active worker.
                                    Cannot be undone.
                                </TooltipContent>
                            </Tooltip>
                            <FeatureInfo note="pipeline.deleteOrphans" />
                        </span>
                    )}
                </TooltipProvider>
            </div>
            {runDisabledReason && (
                <p
                    id={RUN_DISABLED_NOTICE_ID}
                    className="text-xs text-muted-foreground"
                    data-testid="run-pipeline-disabled-reason"
                >
                    {runDisabledReason}
                </p>
            )}
        </div>
    );
};

export default PipelineActionButtons;
