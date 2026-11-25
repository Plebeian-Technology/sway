// @lat: [[mobile-org-membership-components-design#OrgCard#OrgPreferenceSheet wiring]]
import React, { useCallback, useState } from "react";
import { Modal, Pressable as RNPressable, ScrollView, Text, View } from "react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { shadowBold } from "../theme/effects";
import { PreferenceToggle } from "./PreferenceToggle";
import { Pressable } from "./ui/Pressable";
import type { OrgFollowPrefs } from "../hooks/useOrganizationFollow";

export type CadenceValue = "every_change" | "daily" | "weekly";

const CADENCE_OPTIONS: { value: CadenceValue; label: string }[] = [
    { value: "every_change", label: PARITY_COPY.orgNotifications.cadenceEveryChange },
    { value: "daily", label: PARITY_COPY.orgNotifications.cadenceDaily },
    { value: "weekly", label: PARITY_COPY.orgNotifications.cadenceWeekly },
];

// @lat: [[mobile-org-membership-components-design#OrgCard#OrgPreferenceSheet wiring]]
const SHEET_PREF_DEFAULTS = {
    notify_on_new_position: true,
    notify_on_support_change: true,
    notify_on_summary_change: true,
    notification_cadence: "every_change" as CadenceValue,
};

export interface OrgPreferenceSheetProps {
    visible: boolean;
    orgName: string;
    isFirstFollow?: boolean;
    // @lat: [[mobile-org-membership-components-design#OrgCard#OrgPreferenceSheet wiring]]
    initialPrefs?: OrgFollowPrefs;
    onSave: (prefs: OrgFollowPrefs) => Promise<void>;
    onClose: () => void;
    testID?: string;
}

export function OrgPreferenceSheet({
    visible,
    orgName,
    isFirstFollow = false,
    initialPrefs,
    onSave,
    onClose,
    testID = "org-preference-sheet",
}: OrgPreferenceSheetProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    // @lat: [[mobile-org-membership-components-design#OrgCard#OrgPreferenceSheet wiring]]
    const [notifyNewPosition, setNotifyNewPosition] = useState<boolean>(
        initialPrefs?.notify_on_new_position ?? SHEET_PREF_DEFAULTS.notify_on_new_position,
    );
    const [notifySupportChange, setNotifySupportChange] = useState<boolean>(
        initialPrefs?.notify_on_support_change ?? SHEET_PREF_DEFAULTS.notify_on_support_change,
    );
    const [notifySummaryChange, setNotifySummaryChange] = useState<boolean>(
        initialPrefs?.notify_on_summary_change ?? SHEET_PREF_DEFAULTS.notify_on_summary_change,
    );
    const [cadence, setCadence] = useState<CadenceValue>(
        initialPrefs?.notification_cadence ?? SHEET_PREF_DEFAULTS.notification_cadence,
    );
    const [saving, setSaving] = useState<boolean>(false);
    const [saveError, setSaveError] = useState<string | null>(null);

    const handleSave = useCallback(async () => {
        setSaveError(null);
        setSaving(true);
        try {
            await onSave({
                notify_on_new_position: notifyNewPosition,
                notify_on_support_change: notifySupportChange,
                notify_on_summary_change: notifySummaryChange,
                notification_cadence: cadence,
            });
            onClose();
        } catch {
            setSaveError("Couldn't save preferences. Try again.");
        } finally {
            setSaving(false);
        }
    }, [onSave, onClose, notifyNewPosition, notifySupportChange, notifySummaryChange, cadence]);

    return (
        <Modal
            visible={visible}
            transparent
            animationType="slide"
            presentationStyle="overFullScreen"
            onRequestClose={onClose}
            testID={testID}
        >
            <RNPressable
                accessibilityRole="button"
                accessibilityLabel="Dismiss notification preferences"
                onPress={onClose}
                style={{
                    flex: 1,
                    backgroundColor: t.scrim,
                    justifyContent: "flex-end",
                }}
            >
                {/* @lat: [[mobile-chrome-sheets-design#Sheet backdrop: tap-through guard]] */}
                <RNPressable
                    accessibilityRole="none"
                    onPress={() => {}}
                    className="bg-secondary-light dark:bg-secondary-dark rounded-t-2xl border border-border-light dark:border-border-dark"
                >
                    <ScrollView>
                        <View className="p-6 gap-4">
                            <Text
                                className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                                testID="org-pref-sheet-title"
                            >
                                {PARITY_COPY.orgNotifications.prefsTitle}
                            </Text>
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                {PARITY_COPY.orgNotifications.prefsSubtitle(orgName)}
                            </Text>

                            <PreferenceToggle
                                name="notify_on_new_position"
                                label="New position"
                                description="When Sway records a new position from this organization on a bill."
                                value={notifyNewPosition}
                                onValueChange={setNotifyNewPosition}
                                testID="pref-toggle-new-position"
                            />
                            <PreferenceToggle
                                name="notify_on_support_change"
                                label="Support change"
                                description="When Sway records a change in this organization's for/against position."
                                value={notifySupportChange}
                                onValueChange={setNotifySupportChange}
                                testID="pref-toggle-support-change"
                            />
                            <PreferenceToggle
                                name="notify_on_summary_change"
                                label="Summary update"
                                description="When Sway records a change to this organization's position summary."
                                value={notifySummaryChange}
                                onValueChange={setNotifySummaryChange}
                                testID="pref-toggle-summary-change"
                            />

                            {/* @lat: [[mobile-org-membership-components-design#OrgCard#OrgPreferenceSheet wiring]] */}
                            <View className="gap-2">
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    How often
                                </Text>
                                <View
                                    className="flex-row gap-2 flex-wrap"
                                    testID="cadence-picker"
                                    accessibilityLabel="Delivery cadence"
                                >
                                    {CADENCE_OPTIONS.map((opt) => {
                                        const isSelected = cadence === opt.value;
                                        return (
                                            <RNPressable
                                                key={opt.value}
                                                testID={`cadence-${opt.value}`}
                                                accessibilityRole="button"
                                                accessibilityLabel={opt.label}
                                                accessibilityState={{ selected: isSelected }}
                                                onPress={() => setCadence(opt.value)}
                                                className={`min-h-[44px] px-4 py-2 rounded-lg border items-center justify-center ${
                                                    isSelected
                                                        ? "bg-accent-light dark:bg-accent-dark border-accent-light dark:border-accent-dark"
                                                        : "bg-surface-3-light dark:bg-surface-3-dark border-border-strong-light dark:border-border-strong-dark"
                                                }`}
                                                style={isSelected ? shadowBold(colorScheme) : undefined}
                                            >
                                                <Text
                                                    className={`text-sm font-open-sans-semibold ${
                                                        isSelected
                                                            ? "text-white"
                                                            : "text-foreground-light dark:text-foreground-dark"
                                                    }`}
                                                >
                                                    {opt.label}
                                                </Text>
                                            </RNPressable>
                                        );
                                    })}
                                </View>
                            </View>

                            {saveError ? (
                                <Text
                                    testID="org-pref-sheet-error"
                                    accessibilityRole="alert"
                                    className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                                >
                                    {saveError}
                                </Text>
                            ) : null}

                            <Pressable
                                testID="org-pref-sheet-save"
                                accessibilityLabel={PARITY_COPY.orgNotifications.savePreferences}
                                onPress={handleSave}
                                disabled={saving}
                                className="min-h-[44px]"
                            >
                                <Text className="text-sm font-open-sans-semibold text-white py-3">
                                    {PARITY_COPY.orgNotifications.savePreferences}
                                </Text>
                            </Pressable>

                            {isFirstFollow ? (
                                <RNPressable
                                    testID="org-pref-sheet-skip"
                                    accessibilityRole="button"
                                    accessibilityLabel={PARITY_COPY.orgNotifications.skipForNow}
                                    onPress={onClose}
                                    className="min-h-[44px] items-center justify-center"
                                >
                                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {PARITY_COPY.orgNotifications.skipForNow}
                                    </Text>
                                </RNPressable>
                            ) : null}
                        </View>
                    </ScrollView>
                </RNPressable>
            </RNPressable>
        </Modal>
    );
}

export default OrgPreferenceSheet;
