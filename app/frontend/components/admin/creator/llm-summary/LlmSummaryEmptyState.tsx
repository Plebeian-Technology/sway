import { Link, router } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { notify } from "app/frontend/sway_utils";
import { ROUTES } from "app/frontend/sway_constants/routes";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import SummaryRunButton from "app/frontend/components/admin/creator/llm-summary/SummaryRunButton";
import SummarySourcesLedger from "app/frontend/components/admin/creator/llm-summary/SummarySourcesLedger";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Textarea } from "app/frontend/components/ui/textarea";
import LlmSummaryPasteFallback from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPasteFallback";
import LlmSummaryPipelineBusyNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPipelineBusyNotice";
import SummaryModelPicker from "app/frontend/components/admin/creator/llm-summary/SummaryModelPicker";
import { offeredModel } from "app/frontend/components/admin/creator/llm-summary/summaryModelSelection";
import { TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import type {
    IBillPipelineLastFailure,
    ISummaryModelOption,
} from "app/frontend/components/admin/creator/llm-summary/types";
import { useRegenerateSummary } from "app/frontend/components/admin/creator/llm-summary/useRegenerateSummary";

interface IProps {
    // @lat: [[bill-creator-empty-state-prompt-flow#billId is always present]]
    billId: number;
    externalId: string;
    summaryPrompt: string | null;
    billPipelineStatus: TBillPipelineStatus;
    // @lat: [[bill-creator-empty-state-prompt-flow#The pipeline-failure alert]]
    billPipelineFailure: IBillPipelineLastFailure | null;
    isBillPipelineRunning: boolean;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    modelOptions?: ISummaryModelOption[];
    selectedModel?: string;
    onModelChange?: (model: string) => void;
    selectedReasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
}

// @lat: [[bill-creator-empty-state-prompt-flow#IPreparedPromptPage is named, not asserted inline]]
interface IPreparedPromptPage {
    props: {
        bill?: { bill_pipeline_refresh?: { status?: TBillPipelineStatus } | null };
    };
}

// @lat: [[bill-creator-empty-state-prompt-flow#LlmSummaryPasteFallback itself]]
const LlmSummaryEmptyState: React.FC<IProps> = ({
    billId,
    externalId,
    summaryPrompt,
    billPipelineStatus,
    billPipelineFailure,
    isBillPipelineRunning,
    modelOptions = [],
    selectedModel = "",
    onModelChange = () => {},
    selectedReasoningEffort = "",
    onReasoningEffortChange = () => {},
}) => {
    const [showPromptDialog, setShowPromptDialog] = useState<boolean>(false);
    const [isPreparingPrompt, setIsPreparingPrompt] = useState<boolean>(false);

    // @lat: [[bill-creator-empty-state-prompt-flow#Capturing the pipeline status a prompt was built against]]
    const [preparedAtStatus, setPreparedAtStatus] = useState<TBillPipelineStatus>(billPipelineStatus);
    const promptIsStale = summaryPrompt !== null && billPipelineStatus !== preparedAtStatus;

    const { regenLoading, handleRegenerate } = useRegenerateSummary(billId);

    // @lat: [[bill-creator-empty-state-prompt-flow#handlePreparePrompt: a reload, not a post]]
    const handlePreparePrompt = useCallback(() => {
        setIsPreparingPrompt(true);
        // @lat: [[bill-creator-empty-state-prompt-flow#handlePreparePrompt: a reload, not a post]]
        router.reload({
            only: ["summary_prompt", "bill"],
            onSuccess: (page) => {
                const { bill } = (page as unknown as IPreparedPromptPage).props;
                setPreparedAtStatus(bill?.bill_pipeline_refresh?.status ?? billPipelineStatus);
                setShowPromptDialog(true);
            },
            onError: () => notify({ level: "error", title: "Could not build the prompt — try again." }),
            onFinish: () => setIsPreparingPrompt(false),
        });
    }, [billPipelineStatus]);

    const handleCopyPrompt = useCallback(async () => {
        // @lat: [[bill-creator-empty-state-prompt-flow#The pipeline-failure alert]]
        if (!summaryPrompt) {
            notify({ level: "error", title: "The prompt is no longer loaded — prepare it again." });
            return;
        }
        // @lat: [[bill-creator-empty-state-prompt-flow#handleCopyPrompt: refusing to copy is the point]]
        if (promptIsStale) {
            notify({
                level: "error",
                title: "The pipeline changed this bill — prepare the prompt again before copying.",
            });
            return;
        }
        try {
            await navigator.clipboard.writeText(summaryPrompt);
            notify({ level: "success", title: "Prompt copied to clipboard." });
        } catch {
            notify({ level: "error", title: "Could not copy — select the text and copy manually." });
        }
    }, [summaryPrompt, promptIsStale]);

    const activeModel = offeredModel(modelOptions, selectedModel);
    const supportsReasoning = modelOptions.find((opt) => opt.id === activeModel)?.supports_reasoning === true;

    return (
        <div className="flex flex-col gap-3">
            <p data-testid="llm-no-pipeline-data" className="text-sm italic text-muted-foreground">
                No pipeline data available. Run the legislation pipeline for this bill first.
            </p>
            <div className="flex flex-wrap items-center gap-2">
                <SummaryModelPicker
                    modelOptions={modelOptions}
                    selectedModel={selectedModel}
                    onModelChange={onModelChange}
                    selectedReasoningEffort={selectedReasoningEffort}
                    onReasoningEffortChange={onReasoningEffortChange}
                    disabled={isBillPipelineRunning || regenLoading}
                    className="w-full sm:w-40"
                />
                {/* @lat: [[bill-creator-empty-state-prompt-flow#Generate button copy]] */}
                <div className="flex items-center gap-1.5">
                    <SummaryRunButton
                        label="Generate summary"
                        busy={regenLoading}
                        disabled={isBillPipelineRunning}
                        pipelineBlocked={isBillPipelineRunning}
                        onClick={() =>
                            handleRegenerate(
                                activeModel,
                                undefined,
                                supportsReasoning ? selectedReasoningEffort : undefined,
                            )
                        }
                        testId="btn-generate-summary-empty-state"
                        size="sm"
                        title="Runs ONLY the summarize stage against the existing extracted text + parsed sections + diff. Fast — does not re-fetch the PDF."
                    />
                    <FeatureInfo note="summary.generateSummary" />
                </div>
                <div className="flex items-center gap-1.5">
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={handlePreparePrompt}
                        disabled={isPreparingPrompt}
                        data-testid="btn-prepare-prompt"
                    >
                        {isPreparingPrompt ? "Preparing…" : "Prepare prompt"}
                    </Button>
                    <FeatureInfo note="summary.preparePrompt" />
                </div>
                {/* @lat: [[bill-creator-empty-state-prompt-flow#LlmSummaryPasteFallback itself]] */}
                <LlmSummaryPasteFallback billId={billId} size="sm" />
            </div>
            <div className="border-t-neo border-border-soft pt-3">
                <SummarySourcesLedger />
            </div>
            {/* @lat: [[bill-creator-empty-state-prompt-flow#LlmSummaryPipelineBusyNotice reads the same statuses as the button]] */}
            <LlmSummaryPipelineBusyNotice billPipelineStatus={billPipelineStatus} />
            {/* @lat: [[bill-creator-empty-state-prompt-flow#The prompt survives the 5s refresh on purpose]] */}
            {billPipelineFailure && (
                <Alert data-testid="bill-pipeline-error-alert" variant="destructive">
                    <AlertTitle>Pipeline failed</AlertTitle>
                    {/* @lat: [[bill-creator-empty-state-prompt-flow#The pipeline-failure alert]] */}
                    <AlertDescription>
                        {/* @lat: [[bill-creator-empty-state-prompt-flow#The pipeline-failure alert]] */}
                        <span className="tabular-nums lining-nums">{externalId}</span>:{" "}
                        {billPipelineFailure.error_message || "no reason recorded"}
                        {" — "}
                        <Link
                            href={`${ROUTES.billCreatorTab(billId, "pipeline")}?run_id=${billPipelineFailure.run_id}`}
                            className="underline"
                            data-testid="link-failed-run-on-pipeline-tab"
                        >
                            Open this run on the Pipeline tab
                        </Link>
                        {" to resume or restart it."}
                    </AlertDescription>
                </Alert>
            )}

            <Dialog open={showPromptDialog} onOpenChange={(open) => !open && setShowPromptDialog(false)}>
                <DialogContent data-testid="prompt-dialog" className="sm:max-w-2xl">
                    <DialogHeader>
                        <DialogTitle>Bill summary prompt</DialogTitle>
                        {/* @lat: [[bill-creator-empty-state-prompt-flow#No draft_org_positions in the prepared prompt]] */}
                        <DialogDescription>
                            Copy this prompt and paste it into another agent. The agent should return JSON with{" "}
                            <code>summary_markdown</code> (required), plus optionally{" "}
                            <code>full_breakdown_markdown</code>, <code>categories</code>, and{" "}
                            <code>cited_section_keys</code>. Any other key is rejected.
                        </DialogDescription>
                    </DialogHeader>
                    {/* @lat: [[bill-creator-empty-state-prompt-flow#LlmSummaryPasteFallback itself]] */}
                    <p data-testid="prompt-dialog-paste-destination" className="text-sm text-muted-foreground">
                        When the agent replies, close this dialog and use{" "}
                        <span className="font-medium">Paste summary JSON</span> — the button beside{" "}
                        <span className="font-medium">Prepare prompt</span>. No generation is needed, and pasting costs
                        nothing.
                    </p>
                    {/* @lat: [[bill-creator-empty-state-prompt-flow#The prompt survives the 5s refresh on purpose]] */}
                    {promptIsStale && (
                        <Alert data-testid="prompt-dialog-stale" variant="destructive">
                            <AlertTitle>This prompt is out of date</AlertTitle>
                            <AlertDescription>
                                The pipeline changed this bill after the prompt was prepared, so the text below
                                describes an earlier version. Prepare it again before you copy it.
                            </AlertDescription>
                        </Alert>
                    )}
                    <Textarea
                        readOnly
                        rows={16}
                        value={summaryPrompt ?? ""}
                        data-testid="textarea-summary-prompt"
                        aria-describedby={promptIsStale ? "prompt-dialog-stale" : undefined}
                        className="font-mono text-xs"
                    />
                    <DialogFooter>
                        <Button variant="outline" onClick={() => setShowPromptDialog(false)}>
                            Close
                        </Button>
                        {/* @lat: [[bill-creator-empty-state-prompt-flow#The Prepare-again button sits beside the refusal]] */}
                        {promptIsStale && (
                            <Button
                                variant="outline"
                                onClick={handlePreparePrompt}
                                disabled={isPreparingPrompt}
                                data-testid="btn-reprepare-prompt"
                            >
                                {isPreparingPrompt ? "Preparing…" : "Prepare again"}
                            </Button>
                        )}
                        <Button
                            variant="default"
                            onClick={handleCopyPrompt}
                            disabled={promptIsStale}
                            data-testid="btn-copy-prompt"
                        >
                            Copy to clipboard
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </div>
    );
};

export default LlmSummaryEmptyState;
