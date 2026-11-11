import { router } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { landedOnBillCreator } from "app/frontend/components/admin/creator/billCreatorLanding";
import { notify } from "app/frontend/sway_utils";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";

interface IRetainedInstructions {
    billId: number;
    instructions: string;
}

let activeRetainedInstructions: IRetainedInstructions | null = null;

export const getRetainedSummaryInstructions = (billId: number | undefined): string => {
    if (!billId || !activeRetainedInstructions) return "";
    return activeRetainedInstructions.billId === billId ? activeRetainedInstructions.instructions : "";
};

export const setRetainedSummaryInstructions = (billId: number | undefined, instructions: string) => {
    if (!billId) return;
    const trimmed = instructions.replace(/^[\x20\t\r\n\f\v]+|[\x20\t\r\n\f\v]+$/g, "");
    if (trimmed.length > 0) {
        activeRetainedInstructions = { billId, instructions: trimmed };
    } else {
        clearRetainedSummaryInstructions(billId);
    }
};

export const clearRetainedSummaryInstructions = (billId?: number) => {
    if (!billId || activeRetainedInstructions?.billId === billId) {
        activeRetainedInstructions = null;
    }
};

// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
export const useRegenerateSummary = (
    billId: number | undefined,
    supplementalTestimony?: string,
    onRefused?: () => void,
    onAccepted?: () => void,
) => {
    const [regenLoading, setRegenLoading] = useState<boolean>(false);

    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    const handleRegenerate = useCallback(
        (summarizationModel?: string, summaryInstructions?: string, reasoningEffort?: string) => {
            if (!billId) return;
            // @lat: [[bill-creator-summary-tab#How summary-save errors reach the editor#The click event is not a model or instruction]]
            const model = typeof summarizationModel === "string" ? summarizationModel : undefined;
            const rawInstructions = typeof summaryInstructions === "string" ? summaryInstructions : undefined;
            const trimmedInstructions = rawInstructions
                ? rawInstructions.replace(/^[\x20\t\r\n\f\v]+|[\x20\t\r\n\f\v]+$/g, "")
                : "";
            const instructions = trimmedInstructions.length > 0 ? trimmedInstructions : undefined;
            const effort =
                typeof reasoningEffort === "string" && reasoningEffort.length > 0 ? reasoningEffort : undefined;

            if (typeof summaryInstructions === "string") {
                if (instructions) {
                    setRetainedSummaryInstructions(billId, instructions);
                } else {
                    clearRetainedSummaryInstructions(billId);
                }
            }

            router.post(
                `/bills/${billId}/regenerate_summary`,
                {
                    ...(supplementalTestimony === undefined ? {} : { supplemental_testimony: supplementalTestimony }),
                    ...(model ? { summarization_model: model } : {}),
                    ...(instructions ? { summary_instructions: instructions } : {}),
                    ...(effort ? { reasoning_effort: effort } : {}),
                },
                {
                    preserveScroll: true,
                    onStart: () => setRegenLoading(true),
                    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
                    onError: (errors) => {
                        onRefused?.();
                        notifyServerRefusal(errors, "generation", "Could not regenerate the summary.");
                    },
                    onNetworkError: () => {
                        onRefused?.();
                        notify({
                            level: "error",
                            title: "Network error. Could not regenerate the summary.",
                        });
                    },
                    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
                    onSuccess: (page) => {
                        if (pageExpired(page)) {
                            onRefused?.();
                            notify({
                                level: "error",
                                title: "The page expired, so nothing was queued. Try again.",
                            });
                            return;
                        }
                        if (!landedOnBillCreator(page.url, billId)) {
                            onRefused?.();
                            notify({
                                level: "error",
                                title: "Regeneration was not queued. Sign in as an admin and try again.",
                            });
                            return;
                        }
                        clearRetainedSummaryInstructions(billId);
                        onAccepted?.();
                    },
                    onFinish: () => setRegenLoading(false),
                },
            );
        },
        [billId, supplementalTestimony, onRefused, onAccepted],
    );

    return { regenLoading, handleRegenerate };
};
