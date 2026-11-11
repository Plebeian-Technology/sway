import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import SummaryModelPicker from "app/frontend/components/admin/creator/llm-summary/SummaryModelPicker";
import SummaryRunButton from "app/frontend/components/admin/creator/llm-summary/SummaryRunButton";
import { ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    stale: boolean;
    isBillPipelineRunning: boolean;
    isRegenerating: boolean;
    // @lat: [[bill-summary-run-button-unification#Field-level notes]]
    runLoading: boolean;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    modelOptions: ISummaryModelOption[];
    selectedModel: string;
    onModelChange: (model: string) => void;
    selectedReasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
    onShowConfirmDialog: () => void;
    onPasteSummary: () => void;
}

// @lat: [[bill-creator-llm-summary-actions#What LlmSummaryCompletedActions is]]
const LlmSummaryCompletedActions: React.FC<IProps> = ({
    stale,
    isBillPipelineRunning,
    isRegenerating,
    runLoading,
    modelOptions,
    selectedModel,
    onModelChange,
    selectedReasoningEffort,
    onReasoningEffortChange,
    onShowConfirmDialog,
    onPasteSummary,
}) => (
    <>
        {/* @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]] */}
        <SummaryModelPicker
            modelOptions={modelOptions}
            selectedModel={selectedModel}
            onModelChange={onModelChange}
            selectedReasoningEffort={selectedReasoningEffort}
            onReasoningEffortChange={onReasoningEffortChange}
            disabled={isBillPipelineRunning || isRegenerating}
        />
        {!stale && (
            <div className="flex items-center gap-1.5">
                <SummaryRunButton
                    label="Regenerate summary"
                    // @lat: [[bill-summary-run-button-unification#Call-site echoes]]
                    busy={runLoading}
                    disabled={isBillPipelineRunning || isRegenerating}
                    pipelineBlocked={isBillPipelineRunning}
                    onClick={onShowConfirmDialog}
                    testId="btn-regenerate-summary"
                    variant="outline"
                    size="sm"
                    className="w-full sm:w-auto"
                />
                <FeatureInfo note="summary.regenerate" />
            </div>
        )}
        <div className="flex items-center gap-1.5">
            <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={onPasteSummary}
                data-testid="btn-paste-summary-completed"
                className="w-full sm:w-auto"
            >
                Paste summary JSON
            </Button>
            <FeatureInfo note="summary.pasteSummaryJson" />
        </div>
    </>
);

export default LlmSummaryCompletedActions;
