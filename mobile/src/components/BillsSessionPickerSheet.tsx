import React, { useCallback, useState } from "react";
import {
    ActionSheetIOS,
    FlatList,
    Modal,
    Platform,
    Pressable as RNPressable,
    StyleProp,
    Text,
    View,
    ViewStyle,
} from "react-native";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { shadowBold } from "../theme/effects";
import { ListRow } from "./ui/ListRow";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { LegislativeSessionOption } from "../hooks/useBills";

export interface BillsSessionPickerSheetProps {
    sessions: readonly LegislativeSessionOption[];
    selectedSessionId: number | null;
    onSelect: (id: number) => void;
    testID?: string;
}

export function formatLegislativeSessionLabel(session: LegislativeSessionOption): string {
    return session.active ? `${session.name} (Current)` : session.name;
}

export function BillsSessionPickerSheet({
    sessions,
    selectedSessionId,
    onSelect,
    testID,
}: BillsSessionPickerSheetProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const [androidModalVisible, setAndroidModalVisible] = useState(false);

    const selectedSession =
        sessions.find((session) => session.id === selectedSessionId) ??
        sessions.find((session) => session.active) ??
        sessions[0] ??
        null;

    const show = useCallback(() => {
        if (Platform.OS === "ios") {
            ActionSheetIOS.showActionSheetWithOptions(
                {
                    options: [PARITY_COPY.localePicker.cancel, ...sessions.map(formatLegislativeSessionLabel)],
                    cancelButtonIndex: 0,
                    title: PARITY_COPY.bills.sessionLabel,
                },
                (buttonIndex) => {
                    if (buttonIndex > 0) onSelect(sessions[buttonIndex - 1].id);
                },
            );
        } else {
            setAndroidModalVisible(true);
        }
    }, [sessions, onSelect]);

    const currentLabel = selectedSession ? formatLegislativeSessionLabel(selectedSession) : null;
    const styles = [{ minHeight: 44 }, shadowBold(colorScheme)] as StyleProp<ViewStyle>[];

    return (
        <>
            <RNPressable
                testID={testID ?? "bills-session-picker-trigger"}
                onPress={show}
                accessibilityRole="button"
                accessibilityLabel={`${PARITY_COPY.bills.sessionLabel}, currently ${currentLabel ?? "unknown"}`}
                className="bg-surface-3-light dark:bg-surface-3-dark border border-accent-light dark:border-accent-dark rounded-card flex-row items-center justify-between px-4 py-2.5 mx-4 mt-2"
                style={styles}
            >
                <Text className="flex-1 text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {currentLabel
                        ? `${PARITY_COPY.bills.sessionLabel}: ${currentLabel}`
                        : `Select ${PARITY_COPY.bills.sessionLabel.toLowerCase()}`}
                </Text>
                <Text className="text-xl font-open-sans-semibold text-accent-light dark:text-accent-dark">{"›"}</Text>
            </RNPressable>

            {Platform.OS === "android" && (
                <Modal
                    visible={androidModalVisible}
                    transparent
                    animationType="slide"
                    accessibilityViewIsModal
                    onRequestClose={() => setAndroidModalVisible(false)}
                >
                    <RNPressable
                        style={{ flex: 1, backgroundColor: t.scrim }}
                        onPress={() => setAndroidModalVisible(false)}
                    >
                        <View className="absolute bottom-0 left-0 right-0 bg-card-light dark:bg-card-dark rounded-t-lg pb-8">
                            <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark px-4 pt-4 pb-2">
                                {PARITY_COPY.bills.sessionLabel}
                            </Text>
                            <FlatList
                                data={sessions}
                                keyExtractor={(item) => String(item.id)}
                                renderItem={({ item }) => {
                                    const label = formatLegislativeSessionLabel(item);
                                    return (
                                        <ListRow
                                            label={label}
                                            onPress={() => {
                                                onSelect(item.id);
                                                setAndroidModalVisible(false);
                                            }}
                                            accessibilityLabel={label}
                                        />
                                    );
                                }}
                            />
                        </View>
                    </RNPressable>
                </Modal>
            )}
        </>
    );
}
