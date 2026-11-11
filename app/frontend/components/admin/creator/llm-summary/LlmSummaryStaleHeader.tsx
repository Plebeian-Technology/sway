import { Badge } from "app/frontend/components/ui/badge";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import SummaryRunButton from "app/frontend/components/admin/creator/llm-summary/SummaryRunButton";
import { staleChangeLabel, TStaleChangeKind } from "app/frontend/components/admin/creator/llm-summary/staleChange";

interface IProps {
    // @lat: [[stale-change-detection#staleChangeLabel's fallback wording]]
    staleChangeKind: TStaleChangeKind | null;
    staleChangeAt: string | null;
    regenLoading: boolean;
    isGenerationInFlight: boolean;
    // @lat: [[pipeline-busy-terminal-status-inversion#Call-site notes on isBillPipelineRunning]]
    isBillPipelineRunning: boolean;
    // @lat: [[bill-creator-stale-header-layout#onRequestRegenerate opens a confirmation, and used not to]]
    onRequestRegenerate: () => void;
}

// @lat: [[bill-creator-stale-header-layout#Why LlmSummaryStaleHeader is laid out the way it is]]
const LlmSummaryStaleHeader: React.FC<IProps> = ({
    staleChangeKind,
    staleChangeAt,
    regenLoading,
    isGenerationInFlight,
    isBillPipelineRunning,
    onRequestRegenerate,
}) => (
    <div
        data-testid="llm-stale-header"
        className="flex flex-col gap-2 rounded-xl border-neo border-warning bg-warning/12 p-4"
    >
        <div className="flex items-center justify-between gap-2">
            <div className="flex min-w-0 items-center gap-1.5">
                <p className="text-base font-medium">Summary is out of date</p>
                <FeatureInfo note="summary.staleHeader" />
            </div>
            {/* @lat: [[bill-creator-stale-header-layout#The chip is NOT repeated here]] */}
            <TooltipProvider delayDuration={150}>
                <Tooltip>
                    <TooltipTrigger asChild>
                        <Badge variant="stamp" tone="warning" data-testid="llm-stale-chip">
                            {staleChangeLabel(staleChangeKind, staleChangeAt)}
                        </Badge>
                    </TooltipTrigger>
                    {/* @lat: [[bill-creator-stale-header-layout#The hover text follows the chip's own moment]] */}
                    <TooltipContent>{staleChangeAt ?? "unknown"}</TooltipContent>
                </Tooltip>
            </TooltipProvider>
        </div>
        <div>
            <SummaryRunButton
                label="Regenerate from latest data"
                busy={regenLoading}
                disabled={isGenerationInFlight || isBillPipelineRunning}
                pipelineBlocked={isBillPipelineRunning}
                onClick={onRequestRegenerate}
                testId="btn-regenerate-from-latest-data"
                className="w-full sm:w-auto"
            />
        </div>
    </div>
);

export default LlmSummaryStaleHeader;
