// @lat: [[admin-llm-settings-controller-design#LlmSettings.tsx, the frontend page]]

import { Link, router, useForm, usePage, usePoll } from "@inertiajs/react";
import * as React from "react";

import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Combobox, type ComboboxOption } from "app/frontend/components/ui/combobox";
import { Label } from "app/frontend/components/ui/label";
import { Separator } from "app/frontend/components/ui/separator";
import { Switch } from "app/frontend/components/ui/switch";
import ModelSelectField from "app/frontend/components/admin/llm-settings/ModelSelectField";
import type { SupportedModel } from "app/frontend/components/admin/llm-settings/supportedModel";

type UpdatedBy = {
    name: string;
};

interface IProps {
    supported_models: SupportedModel[];
    supported_decision_models?: SupportedModel[];
    supported_extraction_models?: SupportedModel[];
    available_openrouter_models?: Array<{ id: string; label: string }>;
    current_summarization_model: string;
    current_classification_model: string;
    current_decision_model?: string;
    current_extraction_model?: string;
    current_summarization_reasoning_effort?: string | null;
    current_classification_reasoning_effort?: string | null;
    current_summary_batch_enabled: boolean;
    updated_by: UpdatedBy | null;
    updated_at: string;
}

// @lat: [[toasts#Flash toast dedupe#Why per-page flash banners were removed in favor of the global Toaster]]

// @lat: [[admin-llm-settings-stale-write-race#Why POLLING_PROPS bundles the model values with who-changed-it-and-when]]
const POLLING_PROPS = [
    "supported_models",
    "supported_decision_models",
    "supported_extraction_models",
    "available_openrouter_models",
    "current_summarization_model",
    "current_classification_model",
    "current_decision_model",
    "current_extraction_model",
    "current_summarization_reasoning_effort",
    "current_classification_reasoning_effort",
    "current_summary_batch_enabled",
    "updated_by",
    "updated_at",
];

type FormShape = {
    admin_setting: {
        summarization_model: string;
        classification_model: string;
        decision_model: string;
        extraction_model: string;
        summarization_reasoning_effort: string;
        classification_reasoning_effort: string;
        summary_batch_enabled: boolean;
    };
};

// @lat: [[inertia-nested-form-errors-accessor#Reading errors from a nested Inertia form]]
type AdminSettingErrors = {
    summarization_model?: string;
    classification_model?: string;
    decision_model?: string;
    extraction_model?: string;
    summarization_reasoning_effort?: string;
    classification_reasoning_effort?: string;
    summary_batch_enabled?: string;
    offered_models?: string;
};

type TAdminSettingField = keyof AdminSettingErrors;

const BATCH_FIELD_ID = "summary-batch-enabled";
const BATCH_LABEL_ID = `${BATCH_FIELD_ID}-label`;
const BATCH_ERROR_ID = `${BATCH_FIELD_ID}-error`;
const BATCH_DESCRIPTION_ID = `${BATCH_FIELD_ID}-description`;

// @lat: [[inertia-nested-form-errors-accessor#Reading errors from a nested Inertia form]]
const adminSettingError = (errors: unknown, field: TAdminSettingField): string | undefined => {
    const topLevel = (errors as Record<string, string | undefined>)?.[field];
    const flat = (errors as Record<string, string | undefined>)?.[`admin_setting.${field}`];
    const nested = (errors as { admin_setting?: AdminSettingErrors })?.admin_setting?.[field];
    return topLevel ?? flat ?? nested;
};

const LlmSettings: React.FC<IProps> = ({
    supported_models,
    supported_decision_models = supported_models,
    supported_extraction_models = supported_models,
    available_openrouter_models = [],
    current_summarization_model,
    current_classification_model,
    current_decision_model = "",
    current_extraction_model = "",
    current_summarization_reasoning_effort,
    current_classification_reasoning_effort,
    current_summary_batch_enabled,
    updated_by,
    updated_at,
}) => {
    const pageProps = usePage<{ errors?: unknown }>().props;
    const [selectedModelToAdd, setSelectedModelToAdd] = React.useState("");
    const [isRefreshing, setIsRefreshing] = React.useState(false);
    const [isAdding, setIsAdding] = React.useState(false);
    const [removingModelId, setRemovingModelId] = React.useState<string | null>(null);

    const effectiveSelectedModelToAdd = available_openrouter_models.some((m) => m.id === selectedModelToAdd)
        ? selectedModelToAdd
        : "";

    const handleRemoveModel = (modelId: string) => {
        if (removingModelId) return;
        setRemovingModelId(modelId);
        if (form.data.admin_setting.summarization_model === modelId) {
            form.setData("admin_setting.summarization_model", current_summarization_model);
            form.setData("admin_setting.summarization_reasoning_effort", current_summarization_reasoning_effort || "");
        }
        if (form.data.admin_setting.classification_model === modelId) {
            form.setData("admin_setting.classification_model", current_classification_model);
            form.setData(
                "admin_setting.classification_reasoning_effort",
                current_classification_reasoning_effort || "",
            );
        }
        if (form.data.admin_setting.decision_model === modelId) {
            form.setData("admin_setting.decision_model", current_decision_model);
        }
        if (form.data.admin_setting.extraction_model === modelId) {
            form.setData("admin_setting.extraction_model", current_extraction_model);
        }
        router.delete("/admin/llm_settings/remove_model", {
            data: { model_id: modelId },
            preserveScroll: true,
            onFinish: () => {
                setRemovingModelId(null);
            },
        });
    };

    const handleAddModel = () => {
        if (!effectiveSelectedModelToAdd) return;
        setIsAdding(true);
        router.post(
            "/admin/llm_settings/add_model",
            { model_id: effectiveSelectedModelToAdd },
            {
                preserveScroll: true,
                onSuccess: () => {
                    setSelectedModelToAdd("");
                },
                onFinish: () => {
                    setIsAdding(false);
                },
            },
        );
    };

    const handleRefreshModels = () => {
        setIsRefreshing(true);
        router.post(
            "/admin/llm_settings/refresh_models",
            {},
            {
                preserveScroll: true,
                onFinish: () => {
                    setIsRefreshing(false);
                },
            },
        );
    };

    const offeredModels = supported_models.filter((m) => m.selectable);
    const openRouterComboboxOptions: ComboboxOption[] = available_openrouter_models.map((m) => ({
        value: m.id,
        label: m.label,
        keywords: m.id,
    }));

    const form = useForm<FormShape>({
        admin_setting: {
            summarization_model: current_summarization_model,
            classification_model: current_classification_model,
            decision_model: current_decision_model,
            extraction_model: current_extraction_model,
            summarization_reasoning_effort: current_summarization_reasoning_effort || "",
            classification_reasoning_effort: current_classification_reasoning_effort || "",
            summary_batch_enabled: current_summary_batch_enabled,
        },
    });

    // @lat: [[admin-llm-settings-stale-write-race#The fix: a per-field baseline and an expected guard]]
    const [baseline, setBaseline] = React.useState(() => ({
        summarization_model: current_summarization_model,
        classification_model: current_classification_model,
        decision_model: current_decision_model,
        extraction_model: current_extraction_model,
        summarization_reasoning_effort: current_summarization_reasoning_effort || "",
        classification_reasoning_effort: current_classification_reasoning_effort || "",
        summary_batch_enabled: current_summary_batch_enabled,
    }));

    usePoll(15000, { only: POLLING_PROPS });

    const [prevSupportedModels, setPrevSupportedModels] = React.useState(supported_models);
    if (prevSupportedModels !== supported_models) {
        setPrevSupportedModels(supported_models);
        if (
            form.data.admin_setting.summarization_model !== current_summarization_model &&
            !supported_models.some((m) => m.id === form.data.admin_setting.summarization_model)
        ) {
            form.setData("admin_setting.summarization_model", current_summarization_model);
            form.setData("admin_setting.summarization_reasoning_effort", current_summarization_reasoning_effort || "");
            setBaseline((prev) => ({
                ...prev,
                summarization_model: current_summarization_model,
                summarization_reasoning_effort: current_summarization_reasoning_effort || "",
            }));
        }
        if (
            form.data.admin_setting.classification_model !== current_classification_model &&
            !supported_models.some((m) => m.id === form.data.admin_setting.classification_model)
        ) {
            form.setData("admin_setting.classification_model", current_classification_model);
            form.setData(
                "admin_setting.classification_reasoning_effort",
                current_classification_reasoning_effort || "",
            );
            setBaseline((prev) => ({
                ...prev,
                classification_model: current_classification_model,
                classification_reasoning_effort: current_classification_reasoning_effort || "",
            }));
        }
    }

    const [prevSupportedDecisionModels, setPrevSupportedDecisionModels] = React.useState(supported_decision_models);
    if (prevSupportedDecisionModels !== supported_decision_models) {
        setPrevSupportedDecisionModels(supported_decision_models);
        if (
            form.data.admin_setting.decision_model !== current_decision_model &&
            !supported_decision_models.some((m) => m.id === form.data.admin_setting.decision_model)
        ) {
            form.setData("admin_setting.decision_model", current_decision_model);
            setBaseline((prev) => ({
                ...prev,
                decision_model: current_decision_model,
            }));
        }
    }

    const [prevSupportedExtractionModels, setPrevSupportedExtractionModels] =
        React.useState(supported_extraction_models);
    if (prevSupportedExtractionModels !== supported_extraction_models) {
        setPrevSupportedExtractionModels(supported_extraction_models);
        if (
            form.data.admin_setting.extraction_model !== current_extraction_model &&
            !supported_extraction_models.some((m) => m.id === form.data.admin_setting.extraction_model)
        ) {
            form.setData("admin_setting.extraction_model", current_extraction_model);
            setBaseline((prev) => ({
                ...prev,
                extraction_model: current_extraction_model,
            }));
        }
    }

    // @lat: [[admin-llm-settings-stale-write-race#The fix: a per-field baseline and an expected guard]]
    const changedElsewhere =
        current_summarization_model !== baseline.summarization_model ||
        current_classification_model !== baseline.classification_model ||
        current_decision_model !== baseline.decision_model ||
        current_extraction_model !== baseline.extraction_model ||
        (current_summarization_reasoning_effort || "") !== baseline.summarization_reasoning_effort ||
        (current_classification_reasoning_effort || "") !== baseline.classification_reasoning_effort ||
        current_summary_batch_enabled !== baseline.summary_batch_enabled;

    // @lat: [[admin-llm-settings-stale-write-race#Why POLLING_PROPS bundles the model values with who-changed-it-and-when]]
    const adoptCurrentValues = () => {
        setBaseline({
            summarization_model: current_summarization_model,
            classification_model: current_classification_model,
            decision_model: current_decision_model,
            extraction_model: current_extraction_model,
            summarization_reasoning_effort: current_summarization_reasoning_effort || "",
            classification_reasoning_effort: current_classification_reasoning_effort || "",
            summary_batch_enabled: current_summary_batch_enabled,
        });
        form.setData("admin_setting", {
            summarization_model: current_summarization_model,
            classification_model: current_classification_model,
            decision_model: current_decision_model,
            extraction_model: current_extraction_model,
            summarization_reasoning_effort: current_summarization_reasoning_effort || "",
            classification_reasoning_effort: current_classification_reasoning_effort || "",
            summary_batch_enabled: current_summary_batch_enabled,
        });
    };

    const handleSummarizationChange = (val: string) => {
        form.setData("admin_setting.summarization_model", val);
        if (supported_models.find((m) => m.id === val)?.supports_reasoning !== true) {
            form.setData("admin_setting.summarization_reasoning_effort", "");
        }
    };

    const handleClassificationChange = (val: string) => {
        form.setData("admin_setting.classification_model", val);
        if (supported_models.find((m) => m.id === val)?.supports_reasoning !== true) {
            form.setData("admin_setting.classification_reasoning_effort", "");
        }
    };

    const handleDecisionChange = (val: string) => {
        form.setData("admin_setting.decision_model", val);
    };

    const handleExtractionChange = (val: string) => {
        form.setData("admin_setting.extraction_model", val);
    };

    const handleSummarizationReasoningEffortChange = (val: string) => {
        form.setData("admin_setting.summarization_reasoning_effort", val);
    };

    const handleClassificationReasoningEffortChange = (val: string) => {
        form.setData("admin_setting.classification_reasoning_effort", val);
    };

    const handleSummaryBatchEnabledChange = (checked: boolean) => {
        form.setData("admin_setting.summary_batch_enabled", checked);
    };

    // @lat: [[admin-llm-settings-stale-write-race#The fix: a per-field baseline and an expected guard]]
    const buildPayload = () => {
        const changed: Record<string, string | boolean> = {};
        const expected: Record<string, string | boolean> = {};

        if (form.data.admin_setting.summarization_model !== baseline.summarization_model) {
            changed.summarization_model = form.data.admin_setting.summarization_model;
            expected.summarization_model = baseline.summarization_model;
        }
        if (form.data.admin_setting.classification_model !== baseline.classification_model) {
            changed.classification_model = form.data.admin_setting.classification_model;
            expected.classification_model = baseline.classification_model;
        }
        if (form.data.admin_setting.decision_model !== baseline.decision_model) {
            changed.decision_model = form.data.admin_setting.decision_model;
            expected.decision_model = baseline.decision_model;
        }
        if (form.data.admin_setting.extraction_model !== baseline.extraction_model) {
            changed.extraction_model = form.data.admin_setting.extraction_model;
            expected.extraction_model = baseline.extraction_model;
        }
        if (form.data.admin_setting.summarization_reasoning_effort !== baseline.summarization_reasoning_effort) {
            changed.summarization_reasoning_effort = form.data.admin_setting.summarization_reasoning_effort;
            expected.summarization_reasoning_effort = baseline.summarization_reasoning_effort;
        }
        if (form.data.admin_setting.classification_reasoning_effort !== baseline.classification_reasoning_effort) {
            changed.classification_reasoning_effort = form.data.admin_setting.classification_reasoning_effort;
            expected.classification_reasoning_effort = baseline.classification_reasoning_effort;
        }
        if (form.data.admin_setting.summary_batch_enabled !== baseline.summary_batch_enabled) {
            changed.summary_batch_enabled = form.data.admin_setting.summary_batch_enabled;
            expected.summary_batch_enabled = baseline.summary_batch_enabled;
        }

        return { admin_setting: { ...changed, expected } };
    };

    const isDirty =
        form.data.admin_setting.summarization_model !== baseline.summarization_model ||
        form.data.admin_setting.classification_model !== baseline.classification_model ||
        form.data.admin_setting.decision_model !== baseline.decision_model ||
        form.data.admin_setting.extraction_model !== baseline.extraction_model ||
        form.data.admin_setting.summarization_reasoning_effort !== baseline.summarization_reasoning_effort ||
        form.data.admin_setting.classification_reasoning_effort !== baseline.classification_reasoning_effort ||
        form.data.admin_setting.summary_batch_enabled !== baseline.summary_batch_enabled;

    const handleSubmit = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        if (!isDirty) {
            return;
        }
        form.transform(buildPayload);
        form.patch("/admin/llm_settings", {
            preserveScroll: true,
            // @lat: [[admin-llm-settings-stale-write-race#The fix: a per-field baseline and an expected guard]]
            onSuccess: (page) => {
                const nextProps = (page as { props?: Partial<IProps> } | undefined)?.props;
                const nextSummarizationModel =
                    nextProps?.current_summarization_model ?? form.data.admin_setting.summarization_model;
                const nextClassificationModel =
                    nextProps?.current_classification_model ?? form.data.admin_setting.classification_model;
                const nextDecisionModel =
                    nextProps && "current_decision_model" in nextProps
                        ? (nextProps.current_decision_model ?? "")
                        : form.data.admin_setting.decision_model;
                const nextExtractionModel =
                    nextProps && "current_extraction_model" in nextProps
                        ? (nextProps.current_extraction_model ?? "")
                        : form.data.admin_setting.extraction_model;
                const nextSummarizationEffort =
                    nextProps && "current_summarization_reasoning_effort" in nextProps
                        ? nextProps.current_summarization_reasoning_effort || ""
                        : form.data.admin_setting.summarization_reasoning_effort;
                const nextClassificationEffort =
                    nextProps && "current_classification_reasoning_effort" in nextProps
                        ? nextProps.current_classification_reasoning_effort || ""
                        : form.data.admin_setting.classification_reasoning_effort;
                const nextBatchEnabled =
                    nextProps?.current_summary_batch_enabled ?? form.data.admin_setting.summary_batch_enabled;
                const synced = {
                    summarization_model: nextSummarizationModel,
                    classification_model: nextClassificationModel,
                    decision_model: nextDecisionModel,
                    extraction_model: nextExtractionModel,
                    summarization_reasoning_effort: nextSummarizationEffort,
                    classification_reasoning_effort: nextClassificationEffort,
                    summary_batch_enabled: nextBatchEnabled,
                };
                setBaseline(synced);
                form.setData("admin_setting", synced);
            },
        });
    };

    const provenanceCaption = updated_by
        ? `Last changed by ${updated_by.name} at ${new Date(updated_at).toLocaleString()}`
        : "No changes recorded yet.";

    // @lat: [[admin-llm-settings-controller-design#LlmSettings.tsx, the frontend page]]
    const resolveError = (field: TAdminSettingField) =>
        adminSettingError(form.errors, field) ?? adminSettingError(pageProps.errors, field);
    const summarizationError = resolveError("summarization_model");
    const classificationError = resolveError("classification_model");
    const decisionError = resolveError("decision_model");
    const extractionError = resolveError("extraction_model");
    const summarizationReasoningError = resolveError("summarization_reasoning_effort");
    const classificationReasoningError = resolveError("classification_reasoning_effort");
    const summaryBatchError = resolveError("summary_batch_enabled");
    const offeredModelsError = resolveError("offered_models");
    const summaryBatchDescribedBy = [summaryBatchError ? BATCH_ERROR_ID : null, BATCH_DESCRIPTION_ID]
        .filter(Boolean)
        .join(" ");

    return (
        <div className="mx-auto w-full max-w-4xl space-y-6">
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight">LLM Settings</h1>
                <p className="text-sm text-muted-foreground">
                    Select the Claude models used by the bill summarization job and the testimony attachment classifier.
                </p>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle>Model Selection</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4 p-6">
                    <form onSubmit={handleSubmit} className="space-y-6" data-testid="llm-settings-form">
                        {/* @lat: [[admin-llm-settings-stale-write-race#What the "changed elsewhere" banner tells the admin]] */}
                        {changedElsewhere && (
                            <Alert variant="warning" data-testid="llm-settings-changed-elsewhere">
                                <AlertTitle className="line-clamp-none">
                                    {isDirty
                                        ? "Another admin changed these settings while you were choosing. Saving now will be refused."
                                        : "Another admin changed these settings. The models below are the previous ones."}
                                </AlertTitle>
                                <AlertDescription>
                                    <Button
                                        type="button"
                                        variant="outline"
                                        size="sm"
                                        onClick={adoptCurrentValues}
                                        data-testid="btn-llm-settings-load-current"
                                    >
                                        {isDirty
                                            ? "Discard my choice and load the current settings"
                                            : "Load the current settings"}
                                    </Button>
                                </AlertDescription>
                            </Alert>
                        )}

                        <div className="flex items-center justify-between gap-2">
                            <p className="text-sm text-muted-foreground">{provenanceCaption}</p>
                            {/* @lat: [[admin-llm-settings-controller-design#LlmSettings.tsx, the frontend page]] */}
                            <Badge
                                data-testid="llm-settings-provenance-badge"
                                variant={updated_by ? "stamp" : "outline"}
                                tone={updated_by ? "info" : "neutral"}
                            >
                                {updated_by ? "Custom" : "Default"}
                            </Badge>
                        </div>

                        <ModelSelectField
                            id="summarization-model"
                            label="Summarization model"
                            description="Runs once per bill to produce the summary and full breakdown."
                            value={form.data.admin_setting.summarization_model}
                            options={supported_models}
                            reasoningEffort={form.data.admin_setting.summarization_reasoning_effort}
                            onReasoningEffortChange={handleSummarizationReasoningEffortChange}
                            error={summarizationError ?? summarizationReasoningError}
                            onChange={handleSummarizationChange}
                        />

                        <ModelSelectField
                            id="classification-model"
                            label="Testimony classification model"
                            // @lat: [[classification-model-switching-cost#Why CLASSIFIER_MODEL is independent of the summarization default]]
                            description="Decides whether each hearing attachment is testimony or bill text. Runs once per candidate attachment — many calls per bill, where the summary model runs once — so a higher tier raises spend far faster here. Changing it also re-classifies every attachment already decided under the current model, which is a one-time charge on top. Haiku is sized for this call and is the default."
                            value={form.data.admin_setting.classification_model}
                            options={supported_models}
                            reasoningEffort={form.data.admin_setting.classification_reasoning_effort}
                            onReasoningEffortChange={handleClassificationReasoningEffortChange}
                            error={classificationError ?? classificationReasoningError}
                            onChange={handleClassificationChange}
                        />

                        <ModelSelectField
                            id="decision-model"
                            label="Decision model"
                            description="Scores structured choice, yes/no, and scale questions via OpenRouter Decisions API (such as ScaleDown Classify Latest or Jev Latest)."
                            value={form.data.admin_setting.decision_model}
                            options={supported_decision_models}
                            error={decisionError}
                            onChange={handleDecisionChange}
                        />

                        <ModelSelectField
                            id="extraction-model"
                            label="Extraction model"
                            description="Extracts structured organization, role, and quote spans from testimony and news articles (such as ScaleDown Extract Latest)."
                            value={form.data.admin_setting.extraction_model}
                            options={supported_extraction_models}
                            error={extractionError}
                            onChange={handleExtractionChange}
                        />

                        <p className="text-sm text-muted-foreground">
                            <Link
                                href="/admin/system_prompts"
                                className="underline underline-offset-4"
                                data-testid="link-system-prompts"
                            >
                                Read the instructions sent with these models →
                            </Link>
                        </p>

                        <Separator />

                        {/* @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]] */}
                        <div className="space-y-2">
                            <div className="flex items-center gap-3">
                                <Switch
                                    id={BATCH_FIELD_ID}
                                    checked={form.data.admin_setting.summary_batch_enabled}
                                    onCheckedChange={handleSummaryBatchEnabledChange}
                                    aria-labelledby={BATCH_LABEL_ID}
                                    aria-describedby={summaryBatchDescribedBy}
                                    aria-invalid={summaryBatchError ? "true" : undefined}
                                />
                                <Label id={BATCH_LABEL_ID} htmlFor={BATCH_FIELD_ID}>
                                    Batch bill summarization
                                </Label>
                            </div>
                            {summaryBatchError ? (
                                <p id={BATCH_ERROR_ID} role="alert" className="text-sm text-destructive">
                                    {summaryBatchError}
                                </p>
                            ) : null}
                            <p id={BATCH_DESCRIPTION_ID} className="text-sm text-muted-foreground">
                                When this is on, a full pipeline run sends its bill summarization to Claude in batches
                                instead of one call per bill. Batches cost less and are usually faster, but a batch can
                                take up to 24 hours, and its summaries all arrive together rather than bill by bill. It
                                is off by default because the batch path has not yet been proven against a production
                                run.
                            </p>
                        </div>

                        {/* @lat: [[admin-llm-settings-controller-design#LlmSettings.tsx, the frontend page]] */}
                        <Button type="submit" variant="default" disabled={form.processing || !isDirty}>
                            {form.processing ? "Saving..." : "Save settings"}
                        </Button>
                    </form>
                </CardContent>
            </Card>

            {/* @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]] */}
            <Card>
                <CardHeader className="flex flex-col gap-3 space-y-0 pb-4 sm:flex-row sm:items-center sm:justify-between">
                    <div className="space-y-1">
                        <CardTitle>Offered Models</CardTitle>
                        <p className="text-sm text-muted-foreground">
                            Manage the models available for summarization and classification.
                        </p>
                    </div>
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={handleRefreshModels}
                        disabled={isRefreshing}
                        data-testid="btn-refresh-openrouter-models"
                    >
                        {isRefreshing ? "Refreshing..." : "Refresh OpenRouter models"}
                    </Button>
                </CardHeader>
                <CardContent className="space-y-6 p-6 pt-0">
                    {offeredModelsError ? (
                        <p role="alert" className="text-sm text-destructive">
                            {offeredModelsError}
                        </p>
                    ) : null}
                    <div className="space-y-3">
                        <Label className="text-sm font-medium">Currently Offered Models</Label>
                        <ul className="divide-y divide-border rounded-xl border border-border-soft bg-card">
                            {offeredModels.map((model) => {
                                const isActive =
                                    model.id === current_summarization_model ||
                                    model.id === current_classification_model ||
                                    model.id === current_decision_model ||
                                    model.id === current_extraction_model;
                                const isSelectedInForm =
                                    model.id === form.data.admin_setting.summarization_model ||
                                    model.id === form.data.admin_setting.classification_model ||
                                    model.id === form.data.admin_setting.decision_model ||
                                    model.id === form.data.admin_setting.extraction_model;
                                const removeDisabled =
                                    isActive ||
                                    isSelectedInForm ||
                                    offeredModels.length <= 1 ||
                                    removingModelId !== null;
                                return (
                                    <li key={model.id} className="flex items-center justify-between gap-4 p-3 text-sm">
                                        <div className="min-w-0 flex-1">
                                            <p className="truncate font-medium text-foreground">{model.label}</p>
                                            <p className="truncate font-mono text-xs text-muted-foreground">
                                                {model.id}
                                            </p>
                                        </div>
                                        <div className="flex items-center gap-2">
                                            {isActive && (
                                                <Badge variant="outline" tone="neutral" className="text-xs">
                                                    Active
                                                </Badge>
                                            )}
                                            <Button
                                                type="button"
                                                variant="outline"
                                                size="sm"
                                                disabled={removeDisabled}
                                                onClick={() => handleRemoveModel(model.id)}
                                                data-testid={"btn-remove-model-" + model.id}
                                            >
                                                {removingModelId === model.id ? "Removing..." : "Remove"}
                                            </Button>
                                        </div>
                                    </li>
                                );
                            })}
                        </ul>
                    </div>

                    <Separator />

                    <div className="space-y-3">
                        <Label htmlFor="add-openrouter-model" className="text-sm font-medium">
                            Add Model from OpenRouter Catalog
                        </Label>
                        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                            <div className="flex-1">
                                <Combobox
                                    id="add-openrouter-model"
                                    aria-label="Add OpenRouter model"
                                    value={effectiveSelectedModelToAdd}
                                    onValueChange={setSelectedModelToAdd}
                                    options={openRouterComboboxOptions}
                                    placeholder="Select OpenRouter model"
                                    searchPlaceholder="Search OpenRouter catalog..."
                                    emptyText="No matching models."
                                />
                            </div>
                            <Button
                                type="button"
                                variant="default"
                                disabled={!effectiveSelectedModelToAdd || isAdding}
                                onClick={handleAddModel}
                                data-testid="btn-add-openrouter-model"
                            >
                                {isAdding ? "Adding..." : "Add model"}
                            </Button>
                        </div>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
};

export default LlmSettings;
