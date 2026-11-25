// @lat: [[mobile-bill-creator#Sections#The paste summary section]]
import React, { useRef, useState } from "react";
import { Text, TextInput, View } from "react-native";

import { PASTE_SUMMARY_SCHEMA_EXAMPLE } from "../../../../../app/frontend/components/admin/creator/llm-summary/pasteSummarySchemaExample";
import { resolveJsonPointerOffset } from "../../../../../app/frontend/components/admin/creator/paste-summary/resolveJsonPointerOffset";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import { Pressable } from "../../ui/Pressable";
import CollapsibleSection from "./CollapsibleSection";

interface PasteSummarySectionProps {
    billId: number | null;
    refresh: () => Promise<void>;
}

interface PasteSummaryError {
    path: string;
    message: string;
}

interface Selection {
    start: number;
    end: number;
}

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";

const rejectedErrors = (details: Record<string, unknown> | null): PasteSummaryError[] =>
    Array.isArray(details?.errors) ? (details.errors as PasteSummaryError[]) : [];

const PasteSummaryForm: React.FC<{ billId: number; refresh: () => Promise<void>; onClose: () => void }> = ({
    billId,
    refresh,
    onClose,
}) => {
    const [summaryJson, setSummaryJson] = useState("");
    const [selection, setSelection] = useState<Selection | undefined>(undefined);
    const inputRef = useRef<TextInput>(null);
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>(
        "post",
        Routes.billPasteSummary(billId),
    );
    const errors = rejectedErrors(fieldErrors);

    const paste = async () => {
        const response = await run({ summary_json: summaryJson });
        if (response === undefined) return;
        onClose();
        void refresh();
    };

    const showError = (pointer: string) => {
        inputRef.current?.focus();
        const offset = resolveJsonPointerOffset(summaryJson, pointer) ?? 0;
        setSelection({ start: offset, end: offset });
    };

    return (
        <View testID="admin-summary-paste" className="gap-3">
            <Text className={labelText}>Paste bill summary JSON</Text>
            <Text className={bodyText}>
                Paste a valid bill summary JSON payload to create a review draft. The schema is shown below for
                reference.
            </Text>
            <TextInput
                ref={inputRef}
                testID="admin-summary-paste-input"
                accessibilityLabel="Bill summary JSON"
                placeholder='{ "summary_markdown": "...", "full_breakdown_markdown": "..." }'
                multiline
                autoCapitalize="none"
                autoCorrect={false}
                value={summaryJson}
                onChangeText={setSummaryJson}
                selection={selection}
                onSelectionChange={(event) => setSelection(event.nativeEvent.selection)}
                editable={!loading}
                className={`min-h-48 rounded-lg border border-border-light dark:border-border-dark p-3 font-mono ${bodyText}`}
            />
            {errors.length > 0 ? (
                <View testID="admin-summary-paste-errors" className="gap-1">
                    {errors.map((error, index) => (
                        <Pressable
                            key={`${error.path}-${index}`}
                            testID={`admin-summary-paste-error-${index}`}
                            variant="ghost"
                            onPress={() => showError(error.path)}
                        >
                            <Text className={errorText}>
                                <Text className={mutedText}>{error.path}</Text> {error.message}
                            </Text>
                        </Pressable>
                    ))}
                </View>
            ) : errorMessage ? (
                <Text testID="admin-summary-paste-failure" className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
            <CollapsibleSection testID="admin-summary-paste-schema" title="Schema reference">
                <Text testID="admin-summary-paste-schema-example" className={`font-mono ${mutedText}`} selectable>
                    {PASTE_SUMMARY_SCHEMA_EXAMPLE}
                </Text>
            </CollapsibleSection>
            <View className="flex-row flex-wrap gap-2">
                <Pressable testID="admin-summary-paste-cancel" variant="outline" disabled={loading} onPress={onClose}>
                    <Text className={labelText}>Cancel</Text>
                </Pressable>
                <Pressable
                    testID="admin-summary-paste-submit"
                    disabled={loading || summaryJson.trim().length === 0}
                    onPress={() => void paste()}
                >
                    <Text className={labelText}>Validate & paste</Text>
                </Pressable>
            </View>
        </View>
    );
};

const PasteSummarySection: React.FC<PasteSummarySectionProps> = ({ billId, refresh }) => {
    const [open, setOpen] = useState(false);

    if (billId === null) {
        return (
            <View testID="admin-summary-paste" className="px-4 mt-6">
                <Text className={mutedText}>Save the bill before pasting a summary.</Text>
            </View>
        );
    }

    return (
        <View className="px-4 mt-6 gap-3">
            {open ? (
                <PasteSummaryForm billId={billId} refresh={refresh} onClose={() => setOpen(false)} />
            ) : (
                <Pressable testID="admin-summary-paste-open" variant="outline" onPress={() => setOpen(true)}>
                    <Text className={labelText}>Paste summary JSON</Text>
                </Pressable>
            )}
        </View>
    );
};

export default PasteSummarySection;
