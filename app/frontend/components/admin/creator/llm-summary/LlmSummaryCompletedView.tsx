import { useCallback, useState } from "react";
import BillCreatorLlmSummaryBadge from "app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import PasteSummaryDialog from "app/frontend/components/admin/creator/PasteSummaryDialog";
import LlmSummaryBreakdownToggle from "app/frontend/components/admin/creator/llm-summary/LlmSummaryBreakdownToggle";
import LlmSummaryCitationWarning from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCitationWarning";
import LlmSummaryCompletedActions from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedActions";
import LlmSummaryEditableSummary from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEditableSummary";
import LlmSummaryFailedReasonNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryFailedReasonNotice";
import LlmSummaryInFlightNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryInFlightNotice";
import LlmSummaryProvenanceChip from "app/frontend/components/admin/creator/llm-summary/LlmSummaryProvenanceChip";
import LlmSummaryRegenerateConfirmDialog from "app/frontend/components/admin/creator/llm-summary/LlmSummaryRegenerateConfirmDialog";
import LlmSummarySkippedRunNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummarySkippedRunNotice";
import SummarySourcesLedger from "app/frontend/components/admin/creator/llm-summary/SummarySourcesLedger";
import { PASTE_SUMMARY_SCHEMA_EXAMPLE } from "app/frontend/components/admin/creator/llm-summary/pasteSummarySchemaExample";
import { isOperatorPasted } from "app/frontend/components/admin/creator/llm-summary/provenance";
import { PUBLIC_SUMMARY_TITLE_ID } from "app/frontend/components/admin/creator/llm-summary/summaryTitleIds";
import { IBillLlmProvisioning, ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";
import {
    clearRetainedSummaryInstructions,
    getRetainedSummaryInstructions,
    setRetainedSummaryInstructions,
} from "app/frontend/components/admin/creator/llm-summary/useRegenerateSummary";

interface IProps {
    billId: number;
    provisioning: IBillLlmProvisioning;
    // @lat: [[bill-summary-published-vs-draft-box-bug#publishedSummary prop notes]]
    publishedSummary: string;
    isBillPipelineRunning: boolean;
    isRegenerating: boolean;
    // @lat: [[bill-summary-run-button-unification#Field-level notes]]
    runLoading: boolean;
    // @lat: [[bill-creator-llm-summary-status-branching#Which statuses route to the completed view]]
    abandoned: boolean;
    // @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    onConfirmRegenerate: (instructions?: string) => void;
    modelOptions: ISummaryModelOption[];
    selectedModel: string;
    onModelChange: (model: string) => void;
    selectedReasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
}

// @lat: [[bill-creator-completed-view-layout#LlmSummaryInFlightNotice sits above everything it describes]]
// @lat: [[bill-creator-summary-tab#Where the summary stops and the positions start]]
const LlmSummaryCompletedView: React.FC<IProps> = ({
    billId,
    provisioning,
    publishedSummary,
    isBillPipelineRunning,
    isRegenerating,
    runLoading,
    abandoned,
    onConfirmRegenerate,
    modelOptions,
    selectedModel,
    onModelChange,
    selectedReasoningEffort = "",
    onReasoningEffortChange = () => {},
}) => {
    const [showConfirmDialog, setShowConfirmDialog] = useState<boolean>(false);
    const [pasteSummaryOpen, setPasteSummaryOpen] = useState<boolean>(false);

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    const [prevBillId, setPrevBillId] = useState<number>(billId);
    if (billId !== prevBillId) {
        setPrevBillId(billId);
        setShowConfirmDialog(false);
    }

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    if (isRegenerating && showConfirmDialog) setShowConfirmDialog(false);

    const handleConfirmRegenerate = useCallback(
        (instructions?: string) => {
            setShowConfirmDialog(false);
            if (billId && typeof instructions === "string") {
                const trimmed = instructions.replace(/^[\x20\t\r\n\f\v]+|[\x20\t\r\n\f\v]+$/g, "");
                if (trimmed.length > 0) {
                    setRetainedSummaryInstructions(billId, trimmed);
                } else {
                    clearRetainedSummaryInstructions(billId);
                }
            }
            onConfirmRegenerate(instructions);
        },
        [billId, onConfirmRegenerate],
    );

    return (
        <>
            <section
                data-neo-surface="true"
                aria-labelledby={PUBLIC_SUMMARY_TITLE_ID}
                data-testid="panel-public-summary"
                className="flex flex-col gap-4 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo sm:p-6"
            >
                <LlmSummaryInFlightNotice
                    generationStatus={provisioning.generation_status}
                    hasDraft={!!provisioning.llm_summary}
                    pasted={isOperatorPasted(provisioning.llm_provider)}
                    // @lat: [[bill-creator-completed-view-layout#LlmSummaryInFlightNotice sits above everything it describes]]
                    pasteOwnsSummaryRun={provisioning.paste_owns_summary_run}
                    abandoned={abandoned}
                />

                <LlmSummaryCitationWarning
                    citationsValid={provisioning.citations_valid}
                    invalidCitations={provisioning.invalid_citations}
                />

                {/* @lat: [[bill-creator-completed-view-layout#LlmSummaryFailedReasonNotice sits above the editor]] */}
                <LlmSummaryFailedReasonNotice
                    generationStatus={provisioning.generation_status}
                    generationError={provisioning.generation_error}
                    hasDraft={!!provisioning.llm_summary}
                />

                {/* @lat: [[skipped-run-notice-copy#One copy, wherever it is offered]] */}
                <LlmSummarySkippedRunNotice
                    generationStatus={provisioning.generation_status}
                    generationError={provisioning.generation_error}
                    hasDraft={!!provisioning.llm_summary}
                />

                {/* @lat: [[bill-summary-published-vs-draft-box-bug#publishedSummary prop notes]] */}
                <LlmSummaryEditableSummary
                    billId={billId}
                    publishedSummary={publishedSummary}
                    llmDraft={provisioning.llm_summary}
                    llmProvider={provisioning.llm_provider}
                    llmGeneratedAt={provisioning.llm_generated_at}
                    statusSlot={
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="flex items-center gap-1.5">
                                <BillCreatorLlmSummaryBadge
                                    status={provisioning.generation_status}
                                    reclaimable={abandoned}
                                />
                                <FeatureInfo note="summary.runStatusBadge" />
                            </span>
                            <LlmSummaryProvenanceChip llmProvider={provisioning.llm_provider} />
                        </div>
                    }
                    runActions={
                        <LlmSummaryCompletedActions
                            stale={provisioning.stale}
                            isBillPipelineRunning={isBillPipelineRunning}
                            isRegenerating={isRegenerating}
                            runLoading={runLoading}
                            modelOptions={modelOptions}
                            selectedModel={selectedModel}
                            onModelChange={onModelChange}
                            selectedReasoningEffort={selectedReasoningEffort}
                            onReasoningEffortChange={onReasoningEffortChange}
                            onShowConfirmDialog={() => setShowConfirmDialog(true)}
                            onPasteSummary={() => setPasteSummaryOpen(true)}
                        />
                    }
                />

                {/* @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]] */}
                <div className="border-t-neo border-border-soft pt-3">
                    <SummarySourcesLedger />
                </div>

                <div className="border-t-neo border-border-soft pt-3">
                    <LlmSummaryBreakdownToggle breakdown={provisioning.llm_full_breakdown} />
                </div>
            </section>

            {/* @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]] */}
            <LlmSummaryRegenerateConfirmDialog
                key={billId}
                open={showConfirmDialog && !isRegenerating}
                llmProvider={provisioning.llm_provider}
                // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The confirm dialog names the model]]
                modelOptions={modelOptions}
                selectedModel={selectedModel}
                initialInstructions={getRetainedSummaryInstructions(billId)}
                isSubmitting={isRegenerating || runLoading}
                onClose={() => setShowConfirmDialog(false)}
                onConfirm={handleConfirmRegenerate}
                onDiscard={() => clearRetainedSummaryInstructions(billId)}
            />

            <PasteSummaryDialog
                billId={billId}
                open={pasteSummaryOpen}
                onOpenChange={setPasteSummaryOpen}
                schemaExample={PASTE_SUMMARY_SCHEMA_EXAMPLE}
            />
        </>
    );
};

export default LlmSummaryCompletedView;
