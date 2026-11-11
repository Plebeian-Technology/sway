import { useMemo } from "react";
import { Combobox, ComboboxOption } from "app/frontend/components/ui/combobox";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { offeredModel } from "app/frontend/components/admin/creator/llm-summary/summaryModelSelection";
import { ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";
import { cn } from "@/lib/utils";

interface IProps {
    modelOptions: ISummaryModelOption[];
    selectedModel: string;
    onModelChange: (model: string) => void;
    selectedReasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
    disabled?: boolean;
    className?: string;
}

// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
const SummaryModelPicker: React.FC<IProps> = ({
    modelOptions,
    selectedModel,
    onModelChange,
    selectedReasoningEffort,
    onReasoningEffortChange,
    disabled = false,
    className,
}) => {
    const comboboxOptions: ComboboxOption[] = useMemo(
        () =>
            modelOptions.map((opt) => ({
                value: opt.id,
                label: opt.label,
                keywords: opt.id,
            })),
        [modelOptions],
    );

    if (modelOptions.length === 0) return null;

    const activeModel = offeredModel(modelOptions, selectedModel);
    const selectedOption = modelOptions.find((opt) => opt.id === activeModel);
    const supportsReasoning = Boolean(selectedOption?.supports_reasoning);

    return (
        <div className="flex w-full items-center gap-1.5 sm:w-auto">
            <Combobox
                id="summary-model"
                data-testid="select-summary-model"
                aria-label="Model for this run"
                value={activeModel ?? ""}
                onValueChange={onModelChange}
                options={comboboxOptions}
                placeholder="Standing default"
                searchPlaceholder="Search models..."
                emptyText="No matching models."
                disabled={disabled}
                className={cn("h-8 w-auto min-w-36 text-xs", className)}
            />
            {supportsReasoning ? (
                <select
                    id="summary-reasoning-effort"
                    data-testid="select-summary-reasoning-effort"
                    aria-label="Reasoning level for this run"
                    value={selectedReasoningEffort || ""}
                    onChange={(e) => onReasoningEffortChange?.(e.target.value)}
                    disabled={disabled}
                    className="flex h-8 rounded-md border-neo border-border-strong bg-input px-2 text-xs text-foreground shadow-neo transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                >
                    <option value="">Default</option>
                    <option value="low">Low</option>
                    <option value="medium">Medium</option>
                    <option value="high">High</option>
                </select>
            ) : null}
            <FeatureInfo note="summary.modelPicker" />
        </div>
    );
};

export default SummaryModelPicker;
