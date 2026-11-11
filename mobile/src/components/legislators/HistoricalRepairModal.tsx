// @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Historical repair explanations]]
// @lat: [[legislator-history-serialization#Why historical score corrections are embedded directly in term payloads]]
import React from "react";
import { Modal, Pressable, Text, View } from "react-native";
import { ShieldAlert } from "lucide-react-native";

import { useTheme } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { StampedBadge } from "../StampedBadge";
import type { IHistoricalRepairModalProps } from "../../types/legislator";

export function HistoricalRepairModal({
    explanation,
    term,
    legislatorName,
    visible,
    onClose,
}: IHistoricalRepairModalProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    if (!explanation) {
        return null;
    }

    const formattedDelta =
        explanation.delta !== null && explanation.delta !== 0
            ? explanation.delta > 0
                ? `+${explanation.delta}`
                : `${explanation.delta}`
            : null;

    return (
        <Modal
            visible={visible}
            transparent
            animationType="slide"
            presentationStyle="overFullScreen"
            onRequestClose={onClose}
            testID="historical-repair-modal"
        >
            <Pressable
                accessibilityRole="button"
                accessibilityLabel="Dismiss audit explanation"
                onPress={onClose}
                style={{
                    flex: 1,
                    backgroundColor: t.scrim,
                    justifyContent: "flex-end",
                }}
            >
                <Pressable
                    accessibilityRole="none"
                    onPress={() => {}}
                    className="bg-card-light dark:bg-card-dark rounded-t-2xl border-t-2 border-border-strong p-6"
                >
                    <View className="flex-row flex-wrap items-center gap-2 mb-3">
                        <ShieldAlert size={20} color={t.warning} />
                        <StampedBadge label="Authorized Audit" color={t.warning} />
                        {formattedDelta ? <StampedBadge label={`Delta: ${formattedDelta}`} color={t.info} /> : null}
                    </View>

                    <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-1">
                        {explanation.title}
                    </Text>

                    <Text className="text-xs font-open-sans-semibold uppercase tracking-wider text-muted-foreground-light dark:text-muted-foreground-dark mb-4">
                        {term ? `${term.session_label} · ${legislatorName}` : legislatorName}
                    </Text>

                    <View className="bg-surface-2-light dark:bg-surface-2-dark rounded-xl p-4 border border-border-light dark:border-border-dark mb-4">
                        <Text className="text-sm font-open-sans text-foreground-light dark:text-foreground-dark leading-relaxed">
                            {explanation.body}
                        </Text>
                    </View>

                    <View className="bg-surface-3-light dark:bg-surface-3-dark rounded-lg p-3 mb-6 gap-1">
                        <Text className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                            <Text className="font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                Audit Provenance:{" "}
                            </Text>
                            This score adjustment was authorized through {"Sway's"} administrative repair preview and
                            verified against official service records.
                        </Text>
                        <Text className="text-[11px] font-mono text-muted-foreground-light dark:text-muted-foreground-dark opacity-80">
                            Score Reference: {explanation.score_type}
                        </Text>
                    </View>

                    <Pressable
                        onPress={onClose}
                        accessibilityRole="button"
                        accessibilityLabel="Close audit explanation"
                        testID="btn-repair-modal-close"
                        className="min-h-[44px] border border-border-strong bg-surface-2-light dark:bg-surface-2-dark rounded-xl items-center justify-center"
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Close
                        </Text>
                    </Pressable>
                </Pressable>
            </Pressable>
        </Modal>
    );
}

export default HistoricalRepairModal;
