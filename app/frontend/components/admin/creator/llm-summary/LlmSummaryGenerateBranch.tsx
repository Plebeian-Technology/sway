import BillCreatorLlmSummaryBadge from "app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge";
import LlmSummaryAbandonedRunNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryAbandonedRunNotice";
import LlmSummaryPasteFallback from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPasteFallback";
import LlmSummaryQueuedRunNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryQueuedRunNotice";
import LlmSummarySkippedRunNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummarySkippedRunNotice";
import SummaryModelPicker from "app/frontend/components/admin/creator/llm-summary/SummaryModelPicker";
import SummaryRunButton from "app/frontend/components/admin/creator/llm-summary/SummaryRunButton";
import type { ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[bill-creator-generate-branch-layout#What LlmSummaryGenerateBranch.test.tsx tests]]
type TGenerateStatus = "pending" | "failed" | "skipped" | null;

interface IProps {
    // @lat: [[bill-creator-generate-branch-layout#billId is only for the paste fallback]]
    billId: number;
    status: TGenerateStatus;
    generationError: string | null;
    onGenerate: () => void;
    // @lat: [[bill-creator-generate-branch-layout#What LlmSummaryGenerateBranch.test.tsx tests]]
    isBillPipelineRunning: boolean;
    isRegenerating: boolean;
    // @lat: [[bill-creator-generate-branch-layout#Why the abandoned notice can assume "never started" here]]
    abandoned: boolean;
    // @lat: [[bill-creator-generate-branch-layout#hasTestimony]]
    hasTestimony: boolean;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    modelOptions?: ISummaryModelOption[];
    selectedModel?: string;
    onModelChange?: (model: string) => void;
    selectedReasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
}

// @lat: [[bill-creator-generate-branch-layout#abandoned]]
const LlmSummaryGenerateBranch: React.FC<IProps> = ({
    billId,
    status,
    generationError,
    onGenerate,
    isBillPipelineRunning,
    isRegenerating,
    abandoned,
    hasTestimony,
    modelOptions = [],
    selectedModel = "",
    onModelChange = () => {},
    selectedReasoningEffort = "",
    onReasoningEffortChange = () => {},
}) => {
    const isPending = status === "pending";
    const isFailed = status === "failed";
    // @lat: [[bill-creator-generate-branch-layout#What a skipped row is told now lives elsewhere]]

    return (
        <>
            <BillCreatorLlmSummaryBadge status={status} reclaimable={abandoned} />

            {/* @lat: [[bill-creator-generate-branch-layout#No "Pipeline error:" prefix]] */}
            {isFailed && (
                <div data-testid="llm-error-message" className="flex flex-col gap-1">
                    <h4 className="text-sm font-semibold">Summary generation failed</h4>
                    <p className="text-sm text-foreground/80">
                        {generationError || "Sway did not record a reason. Retry, or paste a summary instead."}
                    </p>
                </div>
            )}

            {/* @lat: [[bill-creator-generate-branch-layout#Why the abandoned notice can assume "never started" here]] */}
            {abandoned && <LlmSummaryAbandonedRunNotice generationStatus={status} hasTestimony={hasTestimony} />}

            {/* @lat: [[bill-creator-generate-branch-layout#Why the queued notice is gated on !abandoned]] */}
            {isPending && !abandoned && <LlmSummaryQueuedRunNotice />}

            {/* @lat: [[bill-creator-generate-branch-layout#LlmSummarySkippedRunNotice's hasDraft is false by construction]] */}
            <LlmSummarySkippedRunNotice generationStatus={status} generationError={generationError} hasDraft={false} />

            {/* @lat: [[bill-summary-supersede-gate#The Bill Creator's paste fallback on a skipped row]] */}
            <div className="flex flex-wrap items-center gap-3">
                <SummaryModelPicker
                    modelOptions={modelOptions}
                    selectedModel={selectedModel}
                    onModelChange={onModelChange}
                    selectedReasoningEffort={selectedReasoningEffort}
                    onReasoningEffortChange={onReasoningEffortChange}
                    disabled={(isPending && !abandoned) || isBillPipelineRunning || isRegenerating}
                />
                <SummaryRunButton
                    label={isFailed ? "Retry" : "Generate summary"}
                    // @lat: [[bill-creator-generate-branch-layout#What LlmSummaryGenerateBranch.test.tsx tests]]
                    busy={isRegenerating}
                    // @lat: [[bill-creator-generate-branch-layout#Why the abandoned notice can assume "never started" here]]
                    disabled={(isPending && !abandoned) || isBillPipelineRunning}
                    pipelineBlocked={isBillPipelineRunning}
                    onClick={onGenerate}
                    testId={isFailed ? "btn-retry-summary" : "btn-generate-summary"}
                />
                {status !== null && <LlmSummaryPasteFallback billId={billId} />}
            </div>
        </>
    );
};

export default LlmSummaryGenerateBranch;
