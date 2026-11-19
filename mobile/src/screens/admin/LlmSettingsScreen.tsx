// @lat: [[mobile-admin-area#The LLM settings screen]]
import React, { useState } from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { Routes } from "../../api/routes";
import { PreferenceToggle } from "../../components/PreferenceToggle";
import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { Pressable } from "../../components/ui/Pressable";
import { SegmentedControl } from "../../components/ui/SegmentedControl";
import { useAdminLlmSettings, type AdminLlmSettings, type LlmModelOption } from "../../hooks/admin/useAdminLlmSettings";
import { useAdminMutation } from "../../hooks/admin/useAdminMutation";

export const STALE_SAVE_MESSAGE = "Someone else changed these settings. Pull to refresh, then save again.";

const REASONING_LEVELS = [
    { label: "Default", value: "" },
    { label: "Low", value: "low" },
    { label: "Medium", value: "medium" },
    { label: "High", value: "high" },
];

interface SettingsDraft {
    summarization_model: string;
    classification_model: string;
    decision_model: string;
    extraction_model: string;
    summarization_reasoning_effort: string;
    classification_reasoning_effort: string;
    summary_batch_enabled: boolean;
}

type SettingsField = keyof SettingsDraft;

const draftFrom = (settings: AdminLlmSettings): SettingsDraft => ({
    summarization_model: settings.current_summarization_model,
    classification_model: settings.current_classification_model,
    decision_model: settings.current_decision_model ?? "",
    extraction_model: settings.current_extraction_model ?? "",
    summarization_reasoning_effort: settings.current_summarization_reasoning_effort ?? "",
    classification_reasoning_effort: settings.current_classification_reasoning_effort ?? "",
    summary_batch_enabled: settings.current_summary_batch_enabled,
});

const changedFields = (draft: SettingsDraft, baseline: SettingsDraft): SettingsField[] =>
    (Object.keys(baseline) as SettingsField[]).filter((field) => draft[field] !== baseline[field]);

const buildPayload = (draft: SettingsDraft, baseline: SettingsDraft, fields: SettingsField[]) => {
    const changed: Record<string, string | boolean> = {};
    const expected: Record<string, string | boolean> = {};
    fields.forEach((field) => {
        changed[field] = draft[field];
        expected[field] = baseline[field];
    });
    return { admin_setting: { ...changed, expected } };
};

interface ModelFieldProps {
    field: SettingsField;
    label: string;
    description: string;
    options: LlmModelOption[];
    value: string;
    onChange: (modelId: string) => void;
    reasoningEffort?: string;
    onReasoningEffortChange?: (effort: string) => void;
    disabled: boolean;
}

const ModelField = ({
    field,
    label,
    description,
    options,
    value,
    onChange,
    reasoningEffort,
    onReasoningEffortChange,
    disabled,
}: ModelFieldProps) => {
    const [open, setOpen] = useState(false);
    const testID = `admin-llm-${field}`;
    const selected = options.find((option) => option.id === value);
    const effortIndex = Math.max(
        0,
        REASONING_LEVELS.findIndex((level) => level.value === reasoningEffort),
    );

    return (
        <View testID={testID} className="py-3">
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {label}
            </Text>
            <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {description}
            </Text>
            <Text
                testID={`${testID}-current`}
                className="mt-2 text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
            >
                {selected?.label ?? value}
            </Text>
            <View className="mt-2 flex-row">
                <Pressable
                    testID={`${testID}-toggle`}
                    variant="outline"
                    disabled={disabled}
                    onPress={() => setOpen((wasOpen) => !wasOpen)}
                    accessibilityLabel={`Choose the ${label.toLowerCase()}`}
                    accessibilityState={{ expanded: open }}
                >
                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {open ? "Close" : "Change"}
                    </Text>
                </Pressable>
            </View>
            {open ? (
                <View className="mt-2 gap-2">
                    {options.map((option) => (
                        <Pressable
                            key={option.id}
                            testID={`${testID}-option-${option.id}`}
                            variant={option.id === value ? "default" : "outline"}
                            disabled={!option.selectable}
                            accessibilityRole="radio"
                            accessibilityState={{ selected: option.id === value }}
                            onPress={() => {
                                onChange(option.id);
                                setOpen(false);
                            }}
                        >
                            <Text
                                className={`text-sm font-open-sans-semibold ${
                                    option.id === value
                                        ? "text-primary-foreground-light dark:text-primary-foreground-dark"
                                        : "text-foreground-light dark:text-foreground-dark"
                                }`}
                            >
                                {option.label}
                            </Text>
                        </Pressable>
                    ))}
                </View>
            ) : null}
            {selected?.supports_reasoning && onReasoningEffortChange ? (
                <View className="mt-3">
                    <Text className="mb-2 text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                        Reasoning level
                    </Text>
                    <SegmentedControl
                        testID={`${testID}-effort`}
                        accessibilityLabel={`${label} reasoning level`}
                        segments={REASONING_LEVELS.map((level) => level.label)}
                        selectedIndex={effortIndex}
                        onChange={(index) => onReasoningEffortChange(REASONING_LEVELS[index].value)}
                    />
                </View>
            ) : null}
        </View>
    );
};

const provenanceCaption = (settings: AdminLlmSettings) =>
    settings.updated_by
        ? `Last changed by ${settings.updated_by.name} at ${new Date(settings.updated_at).toLocaleString()}`
        : "No changes recorded yet.";

const LlmSettingsForm = ({ settings, onSaved }: { settings: AdminLlmSettings; onSaved: () => void }) => {
    const baseline = draftFrom(settings);
    const [draft, setDraft] = useState(baseline);
    const { run, loading, errorMessage, errorStatus } = useAdminMutation("patch", Routes.adminLlmSettings());
    const fields = changedFields(draft, baseline);
    const supportedModels = settings.supported_models;

    const setField = <F extends SettingsField>(field: F, value: SettingsDraft[F]) =>
        setDraft((current) => ({ ...current, [field]: value }));

    const chooseModel = (
        modelField: "summarization_model" | "classification_model",
        effortField: "summarization_reasoning_effort" | "classification_reasoning_effort",
        modelId: string,
    ) => {
        const supportsReasoning = supportedModels.find((option) => option.id === modelId)?.supports_reasoning === true;
        setDraft((current) => ({
            ...current,
            [modelField]: modelId,
            [effortField]: supportsReasoning ? current[effortField] : "",
        }));
    };

    const save = async () => {
        const saved = await run(buildPayload(draft, baseline, fields));
        if (saved !== undefined) onSaved();
    };

    return (
        <>
            <Card testID="admin-llm-form" className="mx-4 mb-3">
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {provenanceCaption(settings)}
                </Text>
                <ModelField
                    field="summarization_model"
                    label="Summarization model"
                    description="Runs once per bill to produce the summary and full breakdown."
                    options={supportedModels}
                    value={draft.summarization_model}
                    onChange={(modelId) =>
                        chooseModel("summarization_model", "summarization_reasoning_effort", modelId)
                    }
                    reasoningEffort={draft.summarization_reasoning_effort}
                    onReasoningEffortChange={(effort) => setField("summarization_reasoning_effort", effort)}
                    disabled={loading}
                />
                <ModelField
                    field="classification_model"
                    label="Testimony classification model"
                    description="Decides whether each hearing attachment is testimony or bill text. Runs once per candidate attachment, so a higher tier raises spend far faster here. Changing it also re-classifies every attachment already decided under the current model."
                    options={supportedModels}
                    value={draft.classification_model}
                    onChange={(modelId) =>
                        chooseModel("classification_model", "classification_reasoning_effort", modelId)
                    }
                    reasoningEffort={draft.classification_reasoning_effort}
                    onReasoningEffortChange={(effort) => setField("classification_reasoning_effort", effort)}
                    disabled={loading}
                />
                <ModelField
                    field="decision_model"
                    label="Decision model"
                    description="Scores structured choice, yes/no, and scale questions via the OpenRouter Decisions API."
                    options={settings.supported_decision_models ?? supportedModels}
                    value={draft.decision_model}
                    onChange={(modelId) => setField("decision_model", modelId)}
                    disabled={loading}
                />
                <ModelField
                    field="extraction_model"
                    label="Extraction model"
                    description="Extracts structured organization, role, and quote spans from testimony and news articles."
                    options={settings.supported_extraction_models ?? supportedModels}
                    value={draft.extraction_model}
                    onChange={(modelId) => setField("extraction_model", modelId)}
                    disabled={loading}
                />
                <PreferenceToggle
                    name="summary_batch_enabled"
                    label="Batch bill summarization"
                    description="A full pipeline run sends its summaries to Claude in batches. Batches cost less, but can take up to 24 hours and arrive together. Off by default."
                    value={draft.summary_batch_enabled}
                    onValueChange={(enabled) => setField("summary_batch_enabled", enabled)}
                    disabled={loading}
                />
                {errorMessage ? (
                    <Text
                        testID="admin-llm-error"
                        className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                    >
                        {errorStatus === 409 ? STALE_SAVE_MESSAGE : errorMessage}
                    </Text>
                ) : null}
                <Pressable
                    testID="admin-llm-save"
                    variant="default"
                    disabled={loading || fields.length === 0}
                    onPress={() => void save()}
                    accessibilityLabel="Save the LLM settings"
                >
                    <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                        {loading ? "Saving..." : "Save settings"}
                    </Text>
                </Pressable>
            </Card>
        </>
    );
};

export default function LlmSettingsScreen() {
    const { data, loading, error, refresh } = useAdminLlmSettings();
    const [formVersion, setFormVersion] = useState(0);
    const reload = async () => {
        await refresh();
        setFormVersion((version) => version + 1);
    };

    return (
        <ScrollView
            testID="admin-llm-settings-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            keyboardShouldPersistTaps="handled"
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => void reload()}
                    accessibilityLabel="Pull to refresh the LLM settings"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    LLM settings
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Choose the models behind bill summaries, testimony classification, decisions and extraction.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-llm-settings-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-llm-settings-loading" className="py-12" />
            ) : (
                <LlmSettingsForm key={formVersion} settings={data} onSaved={() => void reload()} />
            )}
        </ScrollView>
    );
}
