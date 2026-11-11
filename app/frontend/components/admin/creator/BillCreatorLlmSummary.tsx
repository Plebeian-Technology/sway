import { router, usePage } from "@inertiajs/react";
import { useCallback, useEffect, useMemo, useState } from "react";
import BillCreatorLlmSummaryStatus from "app/frontend/components/admin/creator/llm-summary/BillCreatorLlmSummaryStatus";
import LlmSummaryEmptyState from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEmptyState";
import BillSummaryRevisionHistory from "app/frontend/components/admin/creator/llm-summary/BillSummaryRevisionHistory";
import { isPipelineBusy } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import {
    clearRetainedSummaryInstructions,
    setRetainedSummaryInstructions,
    useRegenerateSummary,
} from "app/frontend/components/admin/creator/llm-summary/useRegenerateSummary";
import {
    clearRegenerateRequested,
    markRegenerateRequested,
    recallSummaryModel,
    recallSummaryReasoningEffort,
    rememberSummaryModel,
    rememberSummaryReasoningEffort,
} from "app/frontend/components/admin/creator/llm-summary/summaryRunTabMemory";
import { offeredModel } from "app/frontend/components/admin/creator/llm-summary/summaryModelSelection";
import { ISummaryModelOption, TBill } from "app/frontend/components/admin/creator/llm-summary/types";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { landedOnBillCreator } from "app/frontend/components/admin/creator/billCreatorLanding";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import { notify } from "app/frontend/sway_utils";

interface IPageProps {
    bill: TBill;
    summary_prompt?: string | null;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    summary_model_options?: ISummaryModelOption[];
    current_summarization_model?: string | null;
    current_summarization_reasoning_effort?: string | null;
    [key: string]: unknown;
}

const resolveInitialReasoningEffort = (
    targetBillId: number | undefined,
    initialModel: string,
    standingModel: string | null | undefined,
    standingEffort: string | null | undefined,
): string => {
    const recalled = targetBillId ? recallSummaryReasoningEffort(targetBillId) : null;
    if (recalled !== null) {
        return recalled === "default" ? "" : recalled;
    }
    if (initialModel && initialModel === (standingModel ?? "")) {
        return standingEffort ?? "";
    }
    return "";
};

// @lat: [[bill-creator-summary-tab#Where the summary stops and the positions start]]
const BillCreatorLlmSummary: React.FC = () => {
    const pageProps = usePage<IPageProps>().props;
    const bill = pageProps.bill;
    const provisioning = bill.bill_llm_provisioning;

    const billPipelineStatus = bill.bill_pipeline_refresh?.status ?? null;
    const isBillPipelineRunning = isPipelineBusy(billPipelineStatus);

    const [isRegenerating, setIsRegenerating] = useState<boolean>(false);

    const billId = bill.id;
    const [lastBillId, setLastBillId] = useState<number | undefined>(billId);

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    useEffect(() => {
        return () => {
            clearRetainedSummaryInstructions();
        };
    }, []);
    const modelOptions = useMemo(() => pageProps.summary_model_options ?? [], [pageProps.summary_model_options]);
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    const [selectedModel, setSelectedModel] = useState<string>(
        () => (billId ? recallSummaryModel(billId) : null) ?? pageProps.current_summarization_model ?? "",
    );
    const [selectedReasoningEffort, setSelectedReasoningEffort] = useState<string>(() =>
        resolveInitialReasoningEffort(
            billId,
            (billId ? recallSummaryModel(billId) : null) ?? pageProps.current_summarization_model ?? "",
            pageProps.current_summarization_model,
            pageProps.current_summarization_reasoning_effort,
        ),
    );

    if (billId !== lastBillId) {
        setLastBillId(billId);
        clearRetainedSummaryInstructions();
        const nextModel = (billId ? recallSummaryModel(billId) : null) ?? pageProps.current_summarization_model ?? "";
        setSelectedModel(nextModel);
        setSelectedReasoningEffort(
            resolveInitialReasoningEffort(
                billId,
                nextModel,
                pageProps.current_summarization_model,
                pageProps.current_summarization_reasoning_effort,
            ),
        );
    }

    const modelSupportsReasoning = useCallback(
        (modelChoice: string): boolean => {
            const activeModel = offeredModel(modelOptions, modelChoice);
            return modelOptions.find((opt) => opt.id === activeModel)?.supports_reasoning === true;
        },
        [modelOptions],
    );

    const handleModelChange = useCallback(
        (model: string) => {
            setSelectedModel(model);
            if (!modelSupportsReasoning(model)) {
                setSelectedReasoningEffort("");
                if (billId) rememberSummaryReasoningEffort(billId, "");
            } else if (model !== selectedModel) {
                const defaultEffort =
                    model === (pageProps.current_summarization_model ?? "")
                        ? (pageProps.current_summarization_reasoning_effort ?? "")
                        : "";
                setSelectedReasoningEffort(defaultEffort);
                if (billId) rememberSummaryReasoningEffort(billId, "");
            }
            if (billId) rememberSummaryModel(billId, model);
        },
        [
            billId,
            modelSupportsReasoning,
            pageProps.current_summarization_model,
            pageProps.current_summarization_reasoning_effort,
            selectedModel,
        ],
    );

    const handleReasoningEffortChange = useCallback(
        (effort: string) => {
            setSelectedReasoningEffort(effort);
            if (billId) {
                const standingHasEffort =
                    selectedModel === (pageProps.current_summarization_model ?? "") &&
                    Boolean(pageProps.current_summarization_reasoning_effort);
                rememberSummaryReasoningEffort(billId, effort || (standingHasEffort ? "default" : ""));
            }
        },
        [
            billId,
            pageProps.current_summarization_model,
            pageProps.current_summarization_reasoning_effort,
            selectedModel,
        ],
    );

    const resolveOutboundReasoningEffort = useCallback((): string | undefined => {
        if (!modelSupportsReasoning(selectedModel)) return undefined;
        if (selectedReasoningEffort) return selectedReasoningEffort;
        const activeModel = offeredModel(modelOptions, selectedModel);
        if (
            activeModel &&
            activeModel === (pageProps.current_summarization_model ?? "") &&
            Boolean(pageProps.current_summarization_reasoning_effort)
        ) {
            return "default";
        }
        return undefined;
    }, [
        modelOptions,
        modelSupportsReasoning,
        pageProps.current_summarization_model,
        pageProps.current_summarization_reasoning_effort,
        selectedModel,
        selectedReasoningEffort,
    ]);

    const onRefused = useCallback(() => {
        if (billId) clearRegenerateRequested(billId);
    }, [billId]);

    // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]]
    const { regenLoading, handleRegenerate } = useRegenerateSummary(billId, undefined, onRefused);

    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    const onRegenerate = useCallback(
        (instructions?: string) => {
            if (billId) markRegenerateRequested(billId, provisioning?.llm_generated_at ?? null);
            if (billId && typeof instructions === "string") {
                setRetainedSummaryInstructions(billId, instructions);
            }
            handleRegenerate(offeredModel(modelOptions, selectedModel), instructions, resolveOutboundReasoningEffort());
        },
        [
            billId,
            provisioning?.llm_generated_at,
            handleRegenerate,
            modelOptions,
            resolveOutboundReasoningEffort,
            selectedModel,
        ],
    );

    // @lat: [[bill-creator-llm-summary-actions#Why handleGenerate and handleRegenerate are two different code paths]]
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    const handleGenerate = useCallback(() => {
        if (!billId) return;
        const model = offeredModel(modelOptions, selectedModel);
        const outboundEffort = resolveOutboundReasoningEffort();
        setIsRegenerating(true);
        // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]]
        router.post(
            `/bills/${billId}/generate_summary`,
            {
                ...(model ? { summarization_model: model } : {}),
                ...(outboundEffort ? { reasoning_effort: outboundEffort } : {}),
            },
            {
                preserveScroll: true,
                onError: (errors) => notifyServerRefusal(errors, "generation", "Could not start generation."),
                // @lat: [[bill-creator-landed-write-detection#One refusal shares it — call pageExpired first]]
                onSuccess: (page) => {
                    if (pageExpired(page)) {
                        notify({
                            level: "error",
                            title: "The page expired, so nothing was queued. Try again.",
                        });
                        return;
                    }
                    // @lat: [[bill-creator-landed-write-detection#One refusal shares it — call pageExpired first]]
                    if (!landedOnBillCreator(page.url, billId)) {
                        notify({
                            level: "error",
                            title: "Generation was not queued. Sign in as an admin and try again.",
                        });
                    }
                },
                onFinish: () => setIsRegenerating(false),
            },
        );
    }, [billId, modelOptions, resolveOutboundReasoningEffort, selectedModel]);

    const isPersisted = typeof billId === "number" && billId > 0;

    return (
        <div className="flex flex-col gap-4">
            {!provisioning ? (
                <LlmSummaryEmptyState
                    billId={billId}
                    externalId={bill.external_id}
                    summaryPrompt={pageProps.summary_prompt ?? null}
                    billPipelineStatus={billPipelineStatus}
                    billPipelineFailure={bill.bill_pipeline_last_failure ?? null}
                    isBillPipelineRunning={isBillPipelineRunning}
                    modelOptions={modelOptions}
                    selectedModel={selectedModel}
                    onModelChange={handleModelChange}
                    selectedReasoningEffort={selectedReasoningEffort}
                    onReasoningEffortChange={handleReasoningEffortChange}
                />
            ) : (
                <BillCreatorLlmSummaryStatus
                    billId={bill.id}
                    provisioning={provisioning}
                    // @lat: [[bill-creator-llm-summary-actions#Why publishedSummary reads bill.summary, not provisioning.llm_summary]]
                    publishedSummary={bill.summary ?? ""}
                    billPipelineStatus={billPipelineStatus}
                    isBillPipelineRunning={isBillPipelineRunning}
                    isRegenerating={isRegenerating}
                    regenLoading={regenLoading}
                    onRegenerate={onRegenerate}
                    modelOptions={modelOptions}
                    selectedModel={selectedModel}
                    onModelChange={handleModelChange}
                    selectedReasoningEffort={selectedReasoningEffort}
                    onReasoningEffortChange={handleReasoningEffortChange}
                    onGenerate={handleGenerate}
                />
            )}
            {isPersisted && (
                <div className="border-t-neo border-border-soft pt-3">
                    <BillSummaryRevisionHistory billId={billId} currentSummary={bill.summary ?? ""} />
                </div>
            )}
        </div>
    );
};

export default BillCreatorLlmSummary;
