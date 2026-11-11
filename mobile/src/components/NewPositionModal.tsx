// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import React, { useMemo, useState } from "react";
import { FlatList, Modal, Platform, Text, TextInput, TouchableOpacity, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { FormField } from "./ui/FormField";
import { Pressable } from "./ui/Pressable";
import { useOrganizationPositions } from "../hooks/useOrganizationPositions";
import { useBills } from "../hooks/useBills";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { billHeadline } from "../utils/billTitle";
import type { BillRecord } from "../hooks/useBills";

export interface NewPositionModalProps {
    visible: boolean;
    onClose: () => void;
    orgId: number;
    membershipId: number;
    swayLocaleId?: number;
    onSuccess?: () => Promise<void> | void;
}

type SupportValue = "FOR" | "AGAINST";

export function NewPositionModal({
    visible,
    onClose,
    orgId,
    membershipId,
    swayLocaleId = 0,
    onSuccess,
}: NewPositionModalProps) {
    const { propose } = useOrganizationPositions(orgId, membershipId, { enabled: false });
    const { data: bills } = useBills(swayLocaleId, { enabled: visible });

    const [query, setQuery] = useState("");
    const [selectedBillId, setSelectedBillId] = useState<number | null>(null);
    const [support, setSupport] = useState<SupportValue>("FOR");
    const [summary, setSummary] = useState("");
    const [sourceUrl, setSourceUrl] = useState("");
    const [saved, setSaved] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [reloadError, setReloadError] = useState<Error | null>(null);
    const [mutationError, setMutationError] = useState<Error | null>(null);

    const filtered = useMemo(() => {
        const q = query.trim().toLowerCase();
        if (!q) return bills ?? [];
        return (bills ?? []).filter((b) => {
            const externalId = (b.external_id as string | undefined) ?? "";
            const title = (b.title as string | undefined) ?? "";
            const hay = `${externalId} ${title}`.toLowerCase();
            return hay.includes(q);
        });
    }, [bills, query]);

    const resetAndClose = () => {
        setQuery("");
        setSelectedBillId(null);
        setSupport("FOR");
        setSummary("");
        setSourceUrl("");
        setSaved(false);
        setReloadError(null);
        setMutationError(null);
        onClose();
    };

    const handleClose = () => {
        if (isSubmitting) return;
        resetAndClose();
    };

    const handleSubmit = async () => {
        if (!saved && (!selectedBillId || !summary.trim())) return;
        if (isSubmitting) return;

        setIsSubmitting(true);
        setMutationError(null);
        setReloadError(null);
        let didSave = saved;
        try {
            if (!didSave) {
                await propose({
                    bill_id: selectedBillId!,
                    support,
                    summary: summary.trim(),
                    source_url: sourceUrl.trim() || undefined,
                });
                didSave = true;
                setSaved(true);
            }
            await onSuccess?.();
            resetAndClose();
        } catch (err: unknown) {
            const errorObj = err instanceof Error ? err : new Error(String(err));
            if (didSave) {
                setReloadError(errorObj);
            } else {
                setMutationError(errorObj);
            }
        } finally {
            setIsSubmitting(false);
        }
    };

    const selectedBill = (bills ?? []).find((b) => b.id === selectedBillId);

    if (!visible) return null;

    return (
        <Modal
            testID="new-position-modal"
            visible={visible}
            animationType="slide"
            presentationStyle={Platform.OS === "ios" ? "pageSheet" : undefined}
            onRequestClose={handleClose}
        >
            <SafeAreaView className="flex-1 bg-dominant-light dark:bg-dominant-dark">
                <View className="flex-row items-center justify-between px-4 py-3 border-b border-border-light dark:border-border-dark">
                    <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {PARITY_COPY.positions.newModalTitle}
                    </Text>
                    <Pressable variant="ghost" onPress={handleClose} disabled={isSubmitting} accessibilityLabel="Close">
                        <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            Close
                        </Text>
                    </Pressable>
                </View>

                <FlatList
                    keyboardShouldPersistTaps="handled"
                    data={filtered}
                    keyExtractor={(item) => String(item.id)}
                    ListHeaderComponent={
                        <View className="px-4 pt-4 gap-4">
                            {reloadError ? (
                                <View
                                    testID="proposal-reload-error-banner"
                                    className="p-3 rounded-md bg-destructive-light/10 dark:bg-destructive-dark/10"
                                >
                                    <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark">
                                        Position saved, but updating membership failed. Please retry.
                                    </Text>
                                </View>
                            ) : null}
                            {mutationError ? (
                                <View
                                    testID="proposal-mutation-error-banner"
                                    className="p-3 rounded-md bg-destructive-light/10 dark:bg-destructive-dark/10"
                                >
                                    <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark">
                                        {mutationError.message || "Failed to save position. Please try again."}
                                    </Text>
                                </View>
                            ) : null}
                            <View className="mb-4">
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-2">
                                    Bill
                                </Text>
                                <TextInput
                                    testID="new-position-bill-search"
                                    value={query}
                                    onChangeText={setQuery}
                                    placeholder={PARITY_COPY.positions.newBillPickerPlaceholder}
                                    className="border border-border-light dark:border-border-dark rounded-md px-4 py-3 bg-input-light dark:bg-input-dark font-open-sans-light text-foreground-light dark:text-foreground-dark"
                                    style={{ minHeight: 44 }}
                                    accessibilityLabel="Search bills"
                                />
                                {selectedBill ? (
                                    <View className="mt-2 px-3 py-2 bg-surface-3-light dark:bg-surface-3-dark rounded-md">
                                        <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                            Selected: {(selectedBill.external_id as string | undefined) ?? ""}{" "}
                                            {billHeadline((selectedBill.title as string | undefined) ?? "")}
                                        </Text>
                                    </View>
                                ) : null}
                            </View>

                            <View className="mb-4">
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-2">
                                    Position
                                </Text>
                                <View className="flex-row gap-2">
                                    <View className="flex-1">
                                        <Pressable
                                            variant={support === "FOR" ? "default" : "outline"}
                                            onPress={() => setSupport("FOR")}
                                            accessibilityLabel={PARITY_COPY.positions.supports}
                                            accessibilityState={{ selected: support === "FOR" }}
                                        >
                                            <Text
                                                className={`text-sm font-open-sans-semibold ${
                                                    support === "FOR"
                                                        ? "text-primary-foreground-light dark:text-primary-foreground-dark"
                                                        : "text-foreground-light dark:text-foreground-dark"
                                                }`}
                                            >
                                                {PARITY_COPY.positions.supports}
                                            </Text>
                                        </Pressable>
                                    </View>
                                    <View className="flex-1">
                                        <Pressable
                                            variant={support === "AGAINST" ? "destructive" : "outline"}
                                            onPress={() => setSupport("AGAINST")}
                                            accessibilityLabel={PARITY_COPY.positions.opposes}
                                            accessibilityState={{ selected: support === "AGAINST" }}
                                        >
                                            <Text
                                                className={`text-sm font-open-sans-semibold ${
                                                    support === "AGAINST"
                                                        ? "text-white"
                                                        : "text-foreground-light dark:text-foreground-dark"
                                                }`}
                                            >
                                                {PARITY_COPY.positions.opposes}
                                            </Text>
                                        </Pressable>
                                    </View>
                                </View>
                            </View>

                            <FormField
                                label="Summary"
                                value={summary}
                                onChangeText={setSummary}
                                placeholder={PARITY_COPY.positions.newSummaryPlaceholder}
                                testID="new-position-summary"
                            />

                            <FormField
                                label="Source URL (optional)"
                                value={sourceUrl}
                                onChangeText={setSourceUrl}
                                placeholder={PARITY_COPY.positions.newSourceUrlPlaceholder}
                                keyboardType="url"
                                testID="new-position-source-url"
                            />
                        </View>
                    }
                    renderItem={({ item }: { item: BillRecord }) => (
                        <TouchableOpacity
                            testID={`bill-picker-item-${item.id}`}
                            onPress={() => {
                                setSelectedBillId(item.id);
                                setQuery("");
                            }}
                            accessibilityLabel={`Select bill ${(item.external_id as string | undefined) ?? ""} ${billHeadline((item.title as string | undefined) ?? "")}`}
                            className="px-4 py-3 border-b border-border-soft-light dark:border-border-soft-dark"
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {(item.external_id as string | undefined) ?? ""}
                            </Text>
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                {billHeadline((item.title as string | undefined) ?? "")}
                            </Text>
                        </TouchableOpacity>
                    )}
                    ListFooterComponent={
                        <View className="px-4 pb-8 pt-4">
                            <Pressable
                                variant="default"
                                onPress={() => {
                                    void handleSubmit();
                                }}
                                disabled={isSubmitting || (!saved && (!selectedBillId || !summary.trim()))}
                                accessibilityLabel={PARITY_COPY.positions.newSubmitLabel}
                            >
                                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                    {isSubmitting
                                        ? "Saving…"
                                        : saved
                                          ? "Retry refresh"
                                          : PARITY_COPY.positions.newSubmitLabel}
                                </Text>
                            </Pressable>
                        </View>
                    }
                />
            </SafeAreaView>
        </Modal>
    );
}

export default NewPositionModal;
