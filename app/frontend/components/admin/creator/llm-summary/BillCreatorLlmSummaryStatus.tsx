import { usePage } from "@inertiajs/react";
import { Button } from "app/frontend/components/ui/button";
import BillCreatorLlmSummaryBadge from "app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge";
import LlmSummaryAbandonedRunNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryAbandonedRunNotice";
import LlmSummaryCompletedView from "app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedView";
import { TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import LlmSummaryGenerateBranch from "app/frontend/components/admin/creator/llm-summary/LlmSummaryGenerateBranch";
import LlmSummaryStatusShell from "app/frontend/components/admin/creator/llm-summary/LlmSummaryStatusShell";
import { IBillLlmProvisioning, ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";
import SummaryModelPicker from "app/frontend/components/admin/creator/llm-summary/SummaryModelPicker";
import SummaryRunButton from "app/frontend/components/admin/creator/llm-summary/SummaryRunButton";

// @lat: [[bill-creator-llm-summary-status-branching#runInFlight: kept out of shellProps on purpose#Two runs can make a row busy, not one]]
interface IPageProps {
    active_legislation_pipeline_run?: { status?: string | null; bill_id?: number | null } | null;
    [key: string]: unknown;
}

interface IProps {
    billId: number;
    provisioning: IBillLlmProvisioning;
    // @lat: [[bill-summary-published-vs-draft-box-bug#publishedSummary prop notes]]
    publishedSummary: string;
    billPipelineStatus: TBillPipelineStatus;
    isBillPipelineRunning: boolean;
    isRegenerating: boolean;
    regenLoading: boolean;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    onRegenerate: (instructions?: string) => void;
    modelOptions: ISummaryModelOption[];
    selectedModel: string;
    onModelChange: (model: string) => void;
    selectedReasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
    // @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
    onGenerate: () => void;
}

// @lat: [[bill-creator-llm-summary-status-branching#abandoned: derived once above the branch split]]
const BillCreatorLlmSummaryStatus: React.FC<IProps> = ({
    billId,
    provisioning,
    publishedSummary,
    billPipelineStatus,
    isBillPipelineRunning,
    isRegenerating,
    regenLoading,
    onRegenerate,
    onGenerate,
    modelOptions,
    selectedModel,
    onModelChange,
    selectedReasoningEffort = "",
    onReasoningEffortChange = () => {},
}) => {
    // @lat: [[bill-creator-llm-summary-status-branching#One busy flag for both regenerate buttons]]
    const { props: pageProps } = usePage<IPageProps>();
    const isRegenerationInFlight = isRegenerating || regenLoading;
    // @lat: [[bill-creator-llm-summary-status-branching#abandoned: derived once above the branch split]]
    const abandoned = provisioning.reclaimable;
    const shellProps = {
        provisioning,
        billPipelineStatus,
        // @lat: [[bill-creator-llm-summary-status-branching#abandoned: derived once above the branch split]]
        abandoned,
        // @lat: [[pipeline-busy-terminal-status-inversion#Call-site notes on isBillPipelineRunning]]
        isBillPipelineRunning,
        isRegenerating: isRegenerationInFlight,
        regenLoading,
        onRegenerate,
        // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The confirm dialog names the model]]
        modelOptions,
        selectedModel,
    };
    const status = provisioning.generation_status;

    // @lat: [[bill-creator-summary-tab#Which screen a failed run leaves behind]]
    const hasDraftSummary = !!provisioning.llm_summary;
    // @lat: [[bill-creator-llm-summary-status-branching#runInFlight: kept out of shellProps on purpose]]
    const summaryRunInFlight = status === "pending" || status === "generating";
    const activeRun = pageProps.active_legislation_pipeline_run;
    const cleanTestimonyRunning =
        activeRun?.status === "cleaning_testimony" && (activeRun.bill_id === null || activeRun.bill_id === billId);
    const runInFlight = summaryRunInFlight || cleanTestimonyRunning;

    if (status === "completed" || hasDraftSummary) {
        return (
            <LlmSummaryStatusShell {...shellProps}>
                <LlmSummaryCompletedView
                    billId={billId}
                    provisioning={provisioning}
                    publishedSummary={publishedSummary}
                    isBillPipelineRunning={isBillPipelineRunning}
                    // @lat: [[bill-creator-llm-summary-status-branching#Which statuses route to the completed view]]
                    isRegenerating={isRegenerationInFlight || (runInFlight && !abandoned)}
                    // @lat: [[bill-summary-run-button-unification#Field-level notes]]
                    runLoading={isRegenerationInFlight}
                    // @lat: [[bill-creator-llm-summary-status-branching#abandoned: derived once above the branch split]]
                    abandoned={abandoned}
                    modelOptions={modelOptions}
                    selectedModel={selectedModel}
                    onModelChange={onModelChange}
                    selectedReasoningEffort={selectedReasoningEffort}
                    onReasoningEffortChange={onReasoningEffortChange}
                    // @lat: [[bill-creator-llm-summary-status-branching#onConfirmRegenerate: one endpoint for both audit paths]]
                    onConfirmRegenerate={onRegenerate}
                />
            </LlmSummaryStatusShell>
        );
    }

    // @lat: [[bill-creator-llm-summary-status-branching#Only an empty generating row reaches the second branch]]
    if (status === "generating") {
        // @lat: [[bill-creator-llm-summary-status-branching#Only an empty generating row reaches the second branch]]
        return (
            <LlmSummaryStatusShell {...shellProps}>
                <BillCreatorLlmSummaryBadge status="generating" reclaimable={abandoned} />
                {abandoned ? (
                    <>
                        {/* @lat: [[llm-summary-notice-phrase-pairing#The contradiction]] */}
                        <LlmSummaryAbandonedRunNotice
                            generationStatus={status}
                            hasTestimony={provisioning.has_testimony}
                        />
                        <div className="flex flex-wrap items-center gap-3">
                            <SummaryModelPicker
                                modelOptions={modelOptions}
                                selectedModel={selectedModel}
                                onModelChange={onModelChange}
                                selectedReasoningEffort={selectedReasoningEffort}
                                onReasoningEffortChange={onReasoningEffortChange}
                                disabled={isBillPipelineRunning || isRegenerationInFlight}
                            />
                            {/* @lat: [[bill-summary-run-button-unification#Call-site echoes]] */}
                            <SummaryRunButton
                                label="Generate summary"
                                busy={isRegenerationInFlight}
                                disabled={isBillPipelineRunning}
                                pipelineBlocked={isBillPipelineRunning}
                                onClick={onGenerate}
                                testId="btn-start-new-run"
                            />
                        </div>
                    </>
                ) : (
                    <>
                        <p className="text-sm italic text-muted-foreground">Generating summary…</p>
                        <div>
                            {/* @lat: [[bill-summary-run-button-unification#Call-site echoes]] */}
                            <Button type="button" variant="default" disabled>
                                Generating…
                            </Button>
                        </div>
                    </>
                )}
            </LlmSummaryStatusShell>
        );
    }

    return (
        <LlmSummaryStatusShell {...shellProps}>
            <LlmSummaryGenerateBranch
                billId={billId}
                status={status}
                generationError={provisioning.generation_error}
                onGenerate={onGenerate}
                // @lat: [[bill-creator-llm-summary-status-branching#Two disabled reasons stay separate all the way down]]
                isBillPipelineRunning={isBillPipelineRunning}
                isRegenerating={isRegenerationInFlight}
                // @lat: [[bill-creator-llm-summary-status-branching#Only an empty generating row reaches the second branch]]
                abandoned={abandoned}
                hasTestimony={provisioning.has_testimony}
                modelOptions={modelOptions}
                selectedModel={selectedModel}
                onModelChange={onModelChange}
                selectedReasoningEffort={selectedReasoningEffort}
                onReasoningEffortChange={onReasoningEffortChange}
            />
        </LlmSummaryStatusShell>
    );
};

export default BillCreatorLlmSummaryStatus;
