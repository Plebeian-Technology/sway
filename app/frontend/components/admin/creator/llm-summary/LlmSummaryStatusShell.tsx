import { usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import LlmSummaryPipelineBusyNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPipelineBusyNotice";
import { TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import LlmSummaryRegenerateConfirmDialog from "app/frontend/components/admin/creator/llm-summary/LlmSummaryRegenerateConfirmDialog";
import LlmSummaryStaleHeader from "app/frontend/components/admin/creator/llm-summary/LlmSummaryStaleHeader";
import { IBillLlmProvisioning, ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";
import {
    clearRetainedSummaryInstructions,
    getRetainedSummaryInstructions,
    setRetainedSummaryInstructions,
} from "app/frontend/components/admin/creator/llm-summary/useRegenerateSummary";

interface IPageProps {
    bill?: { id?: number };
    [key: string]: unknown;
}

interface IProps {
    provisioning: IBillLlmProvisioning;
    // @lat: [[llm-summary-status-shell#billPipelineStatus goes to the shell, not each branch]]
    billPipelineStatus: TBillPipelineStatus;
    // @lat: [[llm-summary-status-shell#isBillPipelineRunning is derived once by the parent]]
    isBillPipelineRunning: boolean;
    isRegenerating: boolean;
    // @lat: [[llm-summary-status-shell#abandoned]]
    abandoned: boolean;
    regenLoading: boolean;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    onRegenerate: (instructions?: string) => void;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The confirm dialog names the model]]
    modelOptions?: ISummaryModelOption[];
    selectedModel?: string;
    children: React.ReactNode;
}

// @lat: [[llm-summary-status-shell#What LlmSummaryStatusShell is]]
const LlmSummaryStatusShell: React.FC<IProps> = ({
    provisioning,
    billPipelineStatus,
    isBillPipelineRunning,
    isRegenerating,
    abandoned,
    regenLoading,
    onRegenerate,
    modelOptions = [],
    selectedModel = "",
    children,
}) => {
    // @lat: [[llm-summary-status-shell#isGenerationInFlight: greying out the header's button]]
    const isGenerationInFlight =
        (provisioning.generation_status === "pending" || provisioning.generation_status === "generating") && !abandoned;

    const [showStaleConfirm, setShowStaleConfirm] = useState<boolean>(false);

    const { props: pageProps } = usePage<IPageProps>();
    const billId = pageProps.bill?.id;
    const [prevBillId, setPrevBillId] = useState<number | undefined>(billId);
    if (billId !== prevBillId) {
        setPrevBillId(billId);
        setShowStaleConfirm(false);
    }

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    if (isRegenerating && showStaleConfirm) setShowStaleConfirm(false);

    // @lat: [[bill-creator-summary-tab#Where the summary stops and the positions start]]
    const busyLabel = provisioning.llm_summary ? "Regenerating summary…" : "Generating summary…";

    const handleConfirmStaleRegenerate = useCallback(
        (instructions?: string) => {
            setShowStaleConfirm(false);
            if (billId && typeof instructions === "string") {
                const trimmed = instructions.replace(/^[\x20\t\r\n\f\v]+|[\x20\t\r\n\f\v]+$/g, "");
                if (trimmed.length > 0) {
                    setRetainedSummaryInstructions(billId, trimmed);
                } else {
                    clearRetainedSummaryInstructions(billId);
                }
            }
            onRegenerate(instructions);
        },
        [billId, onRegenerate],
    );

    return (
        <div className="flex flex-col gap-4 relative">
            <div className="flex flex-col gap-4" inert={isRegenerating}>
                <LlmSummaryPipelineBusyNotice billPipelineStatus={billPipelineStatus} />
                {provisioning.stale && (
                    <LlmSummaryStaleHeader
                        staleChangeKind={provisioning.stale_change_kind}
                        staleChangeAt={provisioning.stale_change_at}
                        regenLoading={regenLoading}
                        isGenerationInFlight={isGenerationInFlight || isRegenerating}
                        isBillPipelineRunning={isBillPipelineRunning}
                        onRequestRegenerate={() => setShowStaleConfirm(true)}
                    />
                )}
                {children}
            </div>
            {/* @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]] */}
            <LlmSummaryRegenerateConfirmDialog
                key={billId}
                open={showStaleConfirm && !isRegenerating}
                llmProvider={provisioning.llm_provider}
                modelOptions={modelOptions}
                selectedModel={selectedModel}
                initialInstructions={getRetainedSummaryInstructions(billId)}
                isSubmitting={isRegenerating || regenLoading}
                onClose={() => setShowStaleConfirm(false)}
                onConfirm={handleConfirmStaleRegenerate}
                onDiscard={() => clearRetainedSummaryInstructions(billId)}
            />

            {isRegenerating && (
                // @lat: [[llm-summary-status-shell#The busy overlay's aria-live announcement]]
                <output
                    aria-live="polite"
                    data-testid="llm-regenerating-overlay"
                    className="absolute inset-0 flex items-center justify-center rounded-xl bg-card/75 text-xs font-semibold uppercase tracking-widest text-foreground"
                >
                    {busyLabel}
                </output>
            )}
        </div>
    );
};

export default LlmSummaryStatusShell;
