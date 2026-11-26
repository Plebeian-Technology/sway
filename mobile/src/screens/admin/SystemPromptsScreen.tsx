// @lat: [[mobile-admin-area#The system prompts screen]]
import React, { useState } from "react";
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, View } from "react-native";

import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { useSystemPrompts, type SystemPromptEntry } from "../../hooks/admin/useSystemPrompts";

const PROMPT_TEXT_MAX_HEIGHT = 320;

const Badge = ({ label }: { label: string }) => (
    <Text className="rounded-full border border-border-soft-light dark:border-border-soft-dark px-2 py-0.5 text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
        {label}
    </Text>
);

const MutedText = ({ children }: { children: React.ReactNode }) => (
    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
        {children}
    </Text>
);

const ModelRow = ({ label, model }: { label: string; model: string }) => (
    <View className="flex-row flex-wrap items-baseline justify-between gap-2">
        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">{label}</Text>
        <MutedText>{model}</MutedText>
    </View>
);

const PromptCard = ({ entry }: { entry: SystemPromptEntry }) => {
    const [expanded, setExpanded] = useState(false);
    const prompt = entry.system_prompt;

    return (
        <Card testID={`admin-system-prompt-${entry.id}`} className="mx-4 mb-3">
            <Pressable
                accessibilityRole="button"
                accessibilityState={{ expanded }}
                onPress={() => setExpanded((open) => !open)}
            >
                <View className="flex-row flex-wrap items-center gap-2">
                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {entry.label}
                    </Text>
                    {entry.sway_locale_name ? <Badge label={entry.sway_locale_name} /> : null}
                    <Badge
                        label={
                            prompt === null
                                ? "Not sent"
                                : `${(entry.character_count ?? prompt.length).toLocaleString()} characters`
                        }
                    />
                </View>
            </Pressable>
            {expanded ? (
                <View className="gap-2">
                    <MutedText>{entry.purpose}</MutedText>
                    <MutedText>{`Builder: ${entry.builder}`}</MutedText>
                    <MutedText>{`Model: ${entry.model} (${entry.model_setting_label})`}</MutedText>
                    {prompt === null ? (
                        <Text
                            testID={`admin-system-prompt-unavailable-${entry.id}`}
                            className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                        >
                            {entry.unavailable_reason}
                        </Text>
                    ) : (
                        <ScrollView nestedScrollEnabled style={{ maxHeight: PROMPT_TEXT_MAX_HEIGHT }}>
                            <Text
                                selectable
                                testID={`admin-system-prompt-text-${entry.id}`}
                                className="font-mono text-xs text-foreground-light dark:text-foreground-dark"
                            >
                                {prompt}
                            </Text>
                        </ScrollView>
                    )}
                </View>
            ) : null}
        </Card>
    );
};

export default function SystemPromptsScreen() {
    const { catalog, loading, error, refresh } = useSystemPrompts();

    return (
        <ScrollView
            testID="admin-system-prompts-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && catalog !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the system prompts"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    System Prompts
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    The standing instruction half of each model call, read-only. Every real call also carries a user
                    message with its own bill text, testimony or attachments, which is not shown here.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-system-prompts-error" />
            ) : catalog === null ? (
                <ActivityIndicator testID="admin-system-prompts-loading" className="py-12" />
            ) : (
                <>
                    <Card testID="admin-system-prompts-models" className="mx-4 mb-3">
                        <ModelRow label="Summarization model" model={catalog.models.summarization} />
                        <ModelRow label="Testimony classification model" model={catalog.models.classification} />
                    </Card>
                    {catalog.active_category_count === 0 ? (
                        <View className="px-4 pb-3">
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                No active categories
                            </Text>
                            <MutedText>
                                Two of these prompts name the active taxonomy. With none active, the categorisation call
                                is never made and the summary prompt asks for no categories at all.
                            </MutedText>
                        </View>
                    ) : (
                        <View className="px-4 pb-3">
                            <MutedText>
                                {`The bill summary and bill categories prompts name ${catalog.active_category_count} active ${catalog.active_category_count === 1 ? "category" : "categories"}. The other three do not.`}
                            </MutedText>
                        </View>
                    )}
                    {catalog.prompts.map((entry) => (
                        <PromptCard key={entry.id} entry={entry} />
                    ))}
                </>
            )}
        </ScrollView>
    );
}
