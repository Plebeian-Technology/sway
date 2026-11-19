// @lat: [[mobile-admin-area#The LLM model catalog]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Routes } from "../../api/routes";
import { Card } from "../../components/ui/Card";
import { FormField } from "../../components/ui/FormField";
import { Pressable } from "../../components/ui/Pressable";
import { useAdminMutation } from "../../hooks/admin/useAdminMutation";
import type { CatalogModel, LlmModelOption } from "../../hooks/admin/useAdminLlmSettings";

const MAX_CATALOG_RESULTS = 8;

const errorClassName = "text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark";
const mutedClassName = "text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";

interface OfferedModelRowProps {
    model: LlmModelOption;
    removable: boolean;
    inUse: boolean;
    onRemoved: () => void;
}

const OfferedModelRow = ({ model, removable, inUse, onRemoved }: OfferedModelRowProps) => {
    const { run, loading, errorMessage } = useAdminMutation("delete", Routes.adminLlmRemoveModel(model.id));

    const remove = async () => {
        const removed = await run();
        if (removed !== undefined) onRemoved();
    };

    return (
        <View testID={`admin-llm-catalog-model-${model.id}`} className="py-2">
            <View className="flex-row items-center justify-between gap-3">
                <View className="flex-1">
                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {model.label}
                    </Text>
                    <Text className={mutedClassName}>{model.id}</Text>
                </View>
                {inUse ? <Text className={`${mutedClassName} font-open-sans-semibold`}>In use</Text> : null}
                <Pressable
                    testID={`admin-llm-catalog-remove-${model.id}`}
                    variant="outline"
                    disabled={!removable || loading}
                    onPress={() => void remove()}
                    accessibilityLabel={`Remove ${model.label}`}
                >
                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {loading ? "Removing..." : "Remove"}
                    </Text>
                </Pressable>
            </View>
            {errorMessage ? <Text className={errorClassName}>{errorMessage}</Text> : null}
        </View>
    );
};

interface AddModelFormProps {
    catalog: CatalogModel[];
    onAdded: () => void;
}

const AddModelForm = ({ catalog, onAdded }: AddModelFormProps) => {
    const [query, setQuery] = useState("");
    const [chosenId, setChosenId] = useState("");
    const { run, loading, errorMessage } = useAdminMutation("post", Routes.adminLlmAddModel());

    const needle = query.trim().toLowerCase();
    const matches = catalog
        .filter((model) => `${model.label} ${model.id}`.toLowerCase().includes(needle))
        .slice(0, MAX_CATALOG_RESULTS);
    const chosen = catalog.find((model) => model.id === chosenId);

    const add = async () => {
        if (!chosen) return;
        const added = await run({ model_id: chosen.id });
        if (added === undefined) return;
        setChosenId("");
        setQuery("");
        onAdded();
    };

    return (
        <View className="mt-3">
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Add model from the OpenRouter catalog
            </Text>
            <FormField
                testID="admin-llm-catalog-search"
                label="Search the catalog"
                value={query}
                onChangeText={setQuery}
                disabled={loading}
            />
            <View className="mb-3 gap-2">
                {matches.map((model) => (
                    <Pressable
                        key={model.id}
                        testID={`admin-llm-catalog-result-${model.id}`}
                        variant={model.id === chosenId ? "default" : "outline"}
                        disabled={loading}
                        accessibilityRole="radio"
                        accessibilityState={{ selected: model.id === chosenId }}
                        onPress={() => setChosenId(model.id)}
                    >
                        <Text
                            className={`text-sm font-open-sans-semibold ${
                                model.id === chosenId
                                    ? "text-primary-foreground-light dark:text-primary-foreground-dark"
                                    : "text-foreground-light dark:text-foreground-dark"
                            }`}
                        >
                            {model.label}
                        </Text>
                    </Pressable>
                ))}
                {matches.length === 0 ? <Text className={mutedClassName}>No matching models.</Text> : null}
            </View>
            {errorMessage ? <Text className={errorClassName}>{errorMessage}</Text> : null}
            <Pressable
                testID="admin-llm-catalog-add"
                variant="default"
                disabled={!chosen || loading}
                onPress={() => void add()}
                accessibilityLabel="Add the chosen model"
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Adding..." : "Add model"}
                </Text>
            </Pressable>
        </View>
    );
};

interface LlmModelCatalogProps {
    offeredModels: LlmModelOption[];
    catalog: CatalogModel[];
    inUseModelIds: string[];
    onChanged: () => void;
}

export const LlmModelCatalog = ({ offeredModels, catalog, inUseModelIds, onChanged }: LlmModelCatalogProps) => {
    const refresh = useAdminMutation("post", Routes.adminLlmRefreshModels());

    const refreshCatalog = async () => {
        const refreshed = await refresh.run({});
        if (refreshed !== undefined) onChanged();
    };

    return (
        <Card testID="admin-llm-catalog" className="mx-4 mb-3">
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Offered models
            </Text>
            <Text className={`mt-1 ${mutedClassName}`}>
                Manage the models available for summarization and classification.
            </Text>
            <View className="mt-2 flex-row">
                <Pressable
                    testID="admin-llm-catalog-refresh"
                    variant="outline"
                    disabled={refresh.loading}
                    onPress={() => void refreshCatalog()}
                    accessibilityLabel="Refresh the OpenRouter models"
                >
                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {refresh.loading ? "Refreshing..." : "Refresh OpenRouter models"}
                    </Text>
                </Pressable>
            </View>
            {refresh.errorMessage ? <Text className={errorClassName}>{refresh.errorMessage}</Text> : null}
            <View className="mt-2">
                {offeredModels.map((model) => {
                    const inUse = inUseModelIds.includes(model.id);
                    return (
                        <OfferedModelRow
                            key={model.id}
                            model={model}
                            inUse={inUse}
                            removable={!inUse && offeredModels.length > 1}
                            onRemoved={onChanged}
                        />
                    );
                })}
            </View>
            <AddModelForm catalog={catalog} onAdded={onChanged} />
        </Card>
    );
};
