import { Badge } from "app/frontend/components/ui/badge";
import BillCreatorPipelineStatusBadge from "app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

interface IProps {
    status: ILegislationPipelineRun["status"];
    errorCount: number;
    phaseLabel: string | null;
}

const PipelineProgressHeader: React.FC<IProps> = ({ status, errorCount, phaseLabel }) => {
    return (
        <div className="flex flex-wrap items-center gap-2">
            <BillCreatorPipelineStatusBadge status={status} scope="global" />
            <FeatureInfo note="pipeline.statusBadge" />
            {status === "running" && errorCount > 0 && (
                <Badge variant="stamp" tone="warning">
                    <span className="tabular-nums lining-nums">{errorCount}</span>&nbsp;bill error(s)
                </Badge>
            )}
            {phaseLabel && (
                <span
                    data-testid="pipeline-phase"
                    className="break-words text-xs font-semibold uppercase tracking-widest text-muted-foreground"
                >
                    {phaseLabel}
                </span>
            )}
        </div>
    );
};

export default PipelineProgressHeader;
