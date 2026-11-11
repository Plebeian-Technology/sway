// @lat: [[mobile-chrome-sheets-design#DestructiveSheet]]
import React from "react";
import { Modal, Pressable, Text, View } from "react-native";

import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { shadowBold } from "../theme/effects";

export interface DestructiveSheetProps {
    visible: boolean;
    title: string;
    body: string;
    actionLabel: string;
    onConfirm: () => void;
    onDismiss: () => void;
    busy?: boolean;
    testID?: string;
}

export function DestructiveSheet({
    visible,
    title,
    body,
    actionLabel,
    onConfirm,
    onDismiss,
    busy,
    testID = "destructive-sheet",
}: DestructiveSheetProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    return (
        <Modal
            visible={visible}
            transparent
            animationType="slide"
            presentationStyle="overFullScreen"
            onRequestClose={onDismiss}
            testID={testID}
        >
            <Pressable
                accessibilityRole="button"
                accessibilityLabel="Dismiss confirmation"
                onPress={onDismiss}
                style={{
                    flex: 1,
                    backgroundColor: t.scrim,
                    justifyContent: "flex-end",
                }}
            >
                {/* @lat: [[mobile-chrome-sheets-design#Sheet backdrop: tap-through guard]] */}
                <Pressable
                    accessibilityRole="none"
                    onPress={() => {}}
                    className="bg-secondary-light dark:bg-secondary-dark rounded-t-2xl border border-border-light dark:border-border-dark"
                >
                    <View className="p-6">
                        <Text
                            testID="destructive-sheet-title"
                            className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-3"
                        >
                            {title}
                        </Text>
                        <Text
                            testID="destructive-sheet-body"
                            className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark mb-6"
                        >
                            {body}
                        </Text>

                        <Pressable
                            onPress={onConfirm}
                            disabled={!!busy}
                            accessibilityRole="button"
                            accessibilityLabel={actionLabel}
                            accessibilityState={{ disabled: !!busy }}
                            testID="btn-destructive-confirm"
                            className="min-h-[44px] border border-border-light dark:border-border-dark bg-destructive-light dark:bg-destructive-dark rounded-lg items-center justify-center mb-3"
                            style={shadowBold(colorScheme)}
                        >
                            <Text className="text-white text-sm font-open-sans-semibold py-3">
                                {busy ? "…" : actionLabel}
                            </Text>
                        </Pressable>

                        <Pressable
                            onPress={onDismiss}
                            disabled={!!busy}
                            accessibilityRole="link"
                            accessibilityLabel="Cancel"
                            testID="btn-destructive-cancel"
                            className="min-h-[44px] items-center justify-center"
                        >
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                Cancel
                            </Text>
                        </Pressable>
                    </View>
                </Pressable>
            </Pressable>
        </Modal>
    );
}

export default DestructiveSheet;
