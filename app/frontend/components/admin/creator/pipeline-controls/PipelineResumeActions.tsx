import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

interface IPipelineResumeActionsProps {
    failedStageNumber: number | null;
    isPosting: boolean;
    onResume: () => void;
    onRestart: () => void;
}

// @lat: [[pipeline-failed-stage-display#Why PipelineResumeActions dropped the old split button]]
const PipelineResumeActions: React.FC<IPipelineResumeActionsProps> = ({
    failedStageNumber,
    isPosting,
    onResume,
    onRestart,
}) => {
    return (
        <div className="flex flex-wrap items-center gap-3" data-testid="pipeline-resume-actions">
            <Button
                type="button"
                variant="default"
                size="sm"
                onClick={onResume}
                disabled={isPosting}
                data-testid="btn-resume-pipeline"
                className="min-h-[44px] w-full sm:w-auto"
            >
                {failedStageNumber !== null ? `Resume from stage ${failedStageNumber}` : `Resume`}
            </Button>
            <span className="inline-flex w-full items-center gap-1.5 sm:w-auto">
                <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={onRestart}
                    disabled={isPosting}
                    data-testid="btn-restart-pipeline"
                    className="min-h-[44px] w-full sm:w-auto"
                >
                    Restart entire run
                </Button>
                <FeatureInfo note="pipeline.resumeRestart" />
            </span>
        </div>
    );
};

export default PipelineResumeActions;
