import { AlertCircle } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

interface IPipelineFailureHeaderProps {
    run: ILegislationPipelineRun;
    failedStageNumber: number | null;
    failedStageDisplay: string;
    parentShortId: string;
}

// @lat: [[pipeline-failed-stage-display#Pipeline failed-stage display]]
const PipelineFailureHeader: React.FC<IPipelineFailureHeaderProps> = ({
    run,
    failedStageNumber,
    failedStageDisplay,
    parentShortId,
}) => {
    return (
        <Alert variant="destructive" data-testid="pipeline-failure-alert">
            <AlertCircle className="h-4 w-4" />
            <div className="col-start-2 flex items-center gap-1.5">
                <AlertTitle className="min-w-0">
                    {failedStageNumber !== null
                        ? `Failed at stage ${failedStageNumber}: ${failedStageDisplay}`
                        : `Failed during pipeline`}
                </AlertTitle>
                <FeatureInfo note="pipeline.failureHeader" className="shrink-0" />
            </div>
            {(run.origin === "resume" || run.origin === "restart") && parentShortId && (
                <AlertDescription className="text-xs">
                    {run.origin === "resume" ? "Resume" : "Restart"} of run {parentShortId}
                </AlertDescription>
            )}
        </Alert>
    );
};

export default PipelineFailureHeader;
