import { Combobox, type ComboboxOption } from "app/frontend/components/ui/combobox";
import type { SupportedModel } from "app/frontend/components/admin/llm-settings/supportedModel";

interface IProps {
    // @lat: [[admin-setting-model-list#Frontend: ModelSelectField.tsx and supportedModel.ts]]
    id: string;
    label: string;
    description: string;
    value: string;
    options: SupportedModel[];
    reasoningEffort?: string | null;
    onReasoningEffortChange?: (value: string) => void;
    error?: string;
    onChange: (value: string) => void;
}

// @lat: [[admin-setting-model-list#Frontend: ModelSelectField.tsx and supportedModel.ts]]
const ModelSelectField: React.FC<IProps> = ({
    id,
    label,
    description,
    value,
    options,
    reasoningEffort,
    onReasoningEffortChange,
    error,
    onChange,
}) => {
    const errorId = `${id}-error`;
    const descriptionId = `${id}-description`;

    // @lat: [[admin-setting-model-list#Frontend: ModelSelectField.tsx and supportedModel.ts]]
    const describedBy = [error ? errorId : null, descriptionId].filter(Boolean).join(" ");

    const selectedOption = options.find((opt) => opt.id === value);
    const supportsReasoning = Boolean(selectedOption?.supports_reasoning);

    const comboboxOptions: ComboboxOption[] = options.map((option) => ({
        value: option.id,
        label: option.label,
        keywords: option.id,
        disabled: !option.selectable,
    }));

    return (
        <div className="space-y-2">
            <label htmlFor={id} className="text-sm font-medium">
                {label}
            </label>
            <Combobox
                id={id}
                aria-label={label}
                value={value}
                onValueChange={onChange}
                options={comboboxOptions}
                placeholder="Select a model"
                searchPlaceholder="Search models..."
                emptyText="No matching models."
                aria-invalid={error ? true : undefined}
                aria-describedby={describedBy}
            />
            {supportsReasoning ? (
                <div className="space-y-1">
                    <label htmlFor={`${id}-reasoning-effort`} className="text-xs font-medium text-muted-foreground">
                        Reasoning level
                    </label>
                    <select
                        id={`${id}-reasoning-effort`}
                        aria-label={`${label} reasoning level`}
                        aria-invalid={error ? "true" : undefined}
                        aria-describedby={describedBy}
                        value={reasoningEffort || ""}
                        onChange={(e) => onReasoningEffortChange?.(e.target.value)}
                        className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                    >
                        <option value="">Default</option>
                        <option value="low">Low</option>
                        <option value="medium">Medium</option>
                        <option value="high">High</option>
                    </select>
                </div>
            ) : null}
            {error ? (
                <p id={errorId} role="alert" className="text-sm text-destructive">
                    {error}
                </p>
            ) : null}
            <p id={descriptionId} className="text-sm text-muted-foreground">
                {description}
            </p>
        </div>
    );
};

export default ModelSelectField;
