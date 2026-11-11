// @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
import React, { useState } from "react";
import {
    KeyboardAvoidingView,
    Modal,
    Platform,
    Pressable as RNPressable,
    ScrollView,
    Text,
    TextInput,
    View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { CircleCheck } from "lucide-react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { useReportSummary, type ReportSummaryOutcome } from "../hooks/useReportSummary";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import type { SummaryReportReason } from "../types/bill";
import { Pressable } from "./ui/Pressable";

export interface ReportSummarySheetProps {
    visible: boolean;
    billId: number;
    onClose: () => void;
}

const MIN_DETAILS_LENGTH = 10;
const MAX_DETAILS_LENGTH = 2000;

const REASONS: { value: SummaryReportReason; label: string; description: string }[] = [
    {
        value: "factual_inaccuracy",
        label: "Factual inaccuracy",
        description: "Summary contains incorrect facts, wrong numbers, or misstates provisions.",
    },
    {
        value: "misleading_tone",
        label: "Misleading tone or bias",
        description: "Summary uses biased language or presents the bill in a slanted way.",
    },
    {
        value: "missing_amendment",
        label: "Missing amendment or outdated text",
        description: "The bill has been amended, substituted, or withdrawn since this summary was created.",
    },
    {
        value: "other",
        label: "Other issue",
        description: "Formatting error, truncation, or general inaccuracy.",
    },
];

const FAILURE_COPY: Partial<Record<ReportSummaryOutcome, string>> = {
    rate_limited: PARITY_COPY.bill.reportRateLimited,
    offline: PARITY_COPY.bill.reportOffline,
    failed: PARITY_COPY.bill.reportFailed,
};

export function ReportSummarySheet(props: ReportSummarySheetProps) {
    if (!props.visible) return null;
    return <ReportSummaryModal {...props} />;
}

function ReportSummaryModal({ billId, onClose }: ReportSummarySheetProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const { submit, submitting } = useReportSummary(billId);
    const [reason, setReason] = useState<SummaryReportReason | null>(null);
    const [details, setDetails] = useState("");
    const [outcome, setOutcome] = useState<ReportSummaryOutcome | null>(null);

    const canSubmit = reason !== null && details.trim().length >= MIN_DETAILS_LENGTH && !submitting;
    const confirmed = outcome === "submitted" || outcome === "duplicate";
    const failureMessage = outcome === null ? undefined : FAILURE_COPY[outcome];

    const close = () => {
        if (!submitting) onClose();
    };

    const handleSubmit = async () => {
        if (reason === null || !canSubmit) return;
        setOutcome(null);
        setOutcome(await submit(reason, details));
    };

    return (
        <Modal
            testID="report-summary-sheet"
            visible
            animationType="slide"
            presentationStyle={Platform.OS === "ios" ? "pageSheet" : undefined}
            allowSwipeDismissal
            onRequestClose={close}
        >
            <SafeAreaView className="flex-1 bg-dominant-light dark:bg-dominant-dark">
                <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : undefined} className="flex-1">
                    <ScrollView keyboardShouldPersistTaps="handled" contentContainerClassName="p-4 gap-4 pb-8">
                        {confirmed ? (
                            <View testID="report-summary-confirmation" className="items-center gap-3 py-6">
                                <CircleCheck size={40} color={t.success} />
                                <Text
                                    accessibilityRole="header"
                                    className="text-center text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                                >
                                    {PARITY_COPY.bill.reportSubmittedTitle}
                                </Text>
                                <Text className="text-center text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                    {outcome === "duplicate"
                                        ? PARITY_COPY.bill.alreadyReportedNotice
                                        : PARITY_COPY.bill.reportSubmittedMessage}
                                </Text>
                                <Pressable testID="report-summary-done" onPress={onClose} accessibilityLabel="Done">
                                    <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                        Done
                                    </Text>
                                </Pressable>
                            </View>
                        ) : (
                            <>
                                <View className="gap-1">
                                    <Text
                                        accessibilityRole="header"
                                        className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                                    >
                                        {PARITY_COPY.bill.reportDialogTitle}
                                    </Text>
                                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {PARITY_COPY.bill.reportDialogDescription}
                                    </Text>
                                </View>

                                <View accessibilityRole="radiogroup" className="gap-2">
                                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                        What is the issue?
                                    </Text>
                                    {REASONS.map((option) => {
                                        const checked = option.value === reason;
                                        return (
                                            <RNPressable
                                                key={option.value}
                                                testID={`report-summary-reason-${option.value}`}
                                                accessibilityRole="radio"
                                                accessibilityState={{ checked, disabled: submitting }}
                                                accessibilityLabel={`${option.label}. ${option.description}`}
                                                disabled={submitting}
                                                onPress={() => setReason(option.value)}
                                                className={`flex-row items-start gap-3 rounded-xl border p-3 ${
                                                    checked
                                                        ? "border-accent-light bg-surface-3-light dark:border-accent-dark dark:bg-surface-3-dark"
                                                        : "border-border-light bg-card-light dark:border-border-dark dark:bg-card-dark"
                                                }`}
                                                style={{ minHeight: 44 }}
                                            >
                                                <View
                                                    className="mt-0.5 h-5 w-5 items-center justify-center rounded-full border-2"
                                                    style={{ borderColor: checked ? t.accent : t.borderStrong }}
                                                >
                                                    {checked ? (
                                                        <View
                                                            className="h-2.5 w-2.5 rounded-full"
                                                            style={{ backgroundColor: t.accent }}
                                                        />
                                                    ) : null}
                                                </View>
                                                <View className="flex-1 gap-0.5">
                                                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                                        {option.label}
                                                    </Text>
                                                    <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                                        {option.description}
                                                    </Text>
                                                </View>
                                            </RNPressable>
                                        );
                                    })}
                                </View>

                                <View className="gap-2">
                                    <View className="flex-row items-center justify-between gap-2">
                                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                            Details
                                        </Text>
                                        <Text
                                            testID="report-summary-details-count"
                                            className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                                            style={{ fontVariant: ["tabular-nums"] }}
                                        >
                                            {`${details.length}/${MAX_DETAILS_LENGTH}`}
                                        </Text>
                                    </View>
                                    <TextInput
                                        testID="report-summary-details"
                                        value={details}
                                        onChangeText={setDetails}
                                        multiline
                                        maxLength={MAX_DETAILS_LENGTH}
                                        editable={!submitting}
                                        textAlignVertical="top"
                                        placeholder="Explain what is incorrect or misleading, and what the bill actually specifies…"
                                        placeholderTextColor={t.mutedForeground}
                                        accessibilityLabel="Details"
                                        className="rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark"
                                        style={{ minHeight: 112, opacity: submitting ? 0.5 : 1 }}
                                    />
                                    <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                        Minimum {MIN_DETAILS_LENGTH} characters. Please cite sections or specific
                                        wording if possible.
                                    </Text>
                                </View>

                                {failureMessage ? (
                                    <Text
                                        testID="report-summary-error"
                                        accessibilityRole="alert"
                                        accessibilityLiveRegion="polite"
                                        className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                                    >
                                        {failureMessage}
                                    </Text>
                                ) : null}

                                <View className="flex-row gap-3">
                                    <View className="flex-1">
                                        <Pressable
                                            testID="report-summary-cancel"
                                            variant="outline"
                                            onPress={close}
                                            accessibilityLabel="Cancel"
                                        >
                                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                                Cancel
                                            </Text>
                                        </Pressable>
                                    </View>
                                    <View className="flex-1">
                                        <Pressable
                                            testID="report-summary-submit"
                                            onPress={() => void handleSubmit()}
                                            disabled={!canSubmit}
                                            accessibilityLabel="Submit Report"
                                            accessibilityState={{ busy: submitting }}
                                        >
                                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                                {submitting ? "Submitting…" : "Submit Report"}
                                            </Text>
                                        </Pressable>
                                    </View>
                                </View>
                            </>
                        )}
                    </ScrollView>
                </KeyboardAvoidingView>
            </SafeAreaView>
        </Modal>
    );
}

export default ReportSummarySheet;
