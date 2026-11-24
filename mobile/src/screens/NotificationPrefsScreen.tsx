// @lat: [[mobile-notification-prefs-screen#NotificationPrefsScreen]]
import React, { useCallback, useEffect, useRef, useState } from "react";
import {
    AccessibilityInfo,
    ActivityIndicator,
    Linking,
    Pressable as RNPressable,
    ScrollView,
    Text,
    View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import * as Notifications from "expo-notifications";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { PreferenceToggle } from "../components/PreferenceToggle";
import { Card } from "../components/ui/Card";
import { Pressable } from "../components/ui/Pressable";
import { useNotificationPrefs, type NotificationPrefKey } from "../hooks/useNotificationPrefs";
import { apiClient } from "../api/client";
import {
    ApiRequestError,
    GENERIC_ERROR_MESSAGE,
    NetworkError,
    RateLimitedError,
    UnauthorizedError,
} from "../api/errors";
import { Routes } from "../api/routes";
import { useDeviceRegistration } from "../state/DeviceRegistrationContext";
import { useTheme } from "../theme/ThemeProvider";
import { shadowBold } from "../theme/effects";

interface ToggleRowSpec {
    key: NotificationPrefKey;
    label: string;
    description: string;
    defaultEnabled: boolean;
}

const TOGGLE_ROWS: ToggleRowSpec[] = [
    {
        key: "botm_announcement",
        label: PARITY_COPY.notifications.botmAnnouncement.label,
        description: PARITY_COPY.notifications.botmAnnouncement.description,
        defaultEnabled: true,
    },
    {
        key: "legislator_voted",
        label: PARITY_COPY.notifications.legislatorVoted.label,
        description: PARITY_COPY.notifications.legislatorVoted.description,
        defaultEnabled: false,
    },
    {
        key: "vote_window_closing",
        label: PARITY_COPY.notifications.voteWindowClosing.label,
        description: PARITY_COPY.notifications.voteWindowClosing.description,
        defaultEnabled: false,
    },
    {
        key: "org_position_taken",
        label: PARITY_COPY.notifications.orgPositionTaken.label,
        description: PARITY_COPY.notifications.orgPositionTaken.description,
        defaultEnabled: false,
    },
];

type PushUiStatus =
    | "loading"
    | "undetermined"
    | "denied"
    | "granted-pending-registration"
    | "granted-and-registered"
    | "test-sent"
    | "test-send-error";

type CadenceValue = "every_change" | "daily" | "weekly";

const CADENCE_OPTIONS: { value: CadenceValue; label: string }[] = [
    { value: "every_change", label: PARITY_COPY.orgNotifications.cadenceEveryChange },
    { value: "daily", label: PARITY_COPY.orgNotifications.cadenceDaily },
    { value: "weekly", label: PARITY_COPY.orgNotifications.cadenceWeekly },
];

interface OrgDefaultsPayload {
    org_position_taken?: boolean | null;
    org_position_cadence_default?: CadenceValue;
    notify_on_new_position_default?: boolean;
    notify_on_support_change_default?: boolean;
    notify_on_summary_change_default?: boolean;
}

type SaveState = { kind: "idle" } | { kind: "saving" } | { kind: "saved" } | { kind: "error"; message: string };

const SAVED_VISIBLE_MS = 4000;

function saveErrorMessage(e: unknown): string {
    if (
        e instanceof ApiRequestError &&
        !(e instanceof NetworkError) &&
        !(e instanceof UnauthorizedError) &&
        !(e instanceof RateLimitedError) &&
        e.status !== undefined &&
        e.status >= 400 &&
        e.status < 500 &&
        e.message &&
        e.message !== GENERIC_ERROR_MESSAGE
    ) {
        return e.message;
    }
    return PARITY_COPY.notifications.saveError;
}

// @lat: [[mobile-notification-prefs-screen#Save feedback and pinned footer]]
function useOrgDefaultsForm() {
    const [loading, setLoading] = useState<boolean>(true);
    const [loadError, setLoadError] = useState<string | null>(null);
    const [saveState, setSaveState] = useState<SaveState>({ kind: "idle" });
    const inFlight = useRef<boolean>(false);

    const [notifyNewPos, setNotifyNewPosRaw] = useState<boolean>(true);
    const [notifySupportChange, setNotifySupportChangeRaw] = useState<boolean>(true);
    const [notifySummaryChange, setNotifySummaryChangeRaw] = useState<boolean>(true);
    const [cadence, setCadenceRaw] = useState<CadenceValue>("every_change");

    const dismissStatus = useCallback(() => {
        setSaveState((prev) => (prev.kind === "saved" || prev.kind === "error" ? { kind: "idle" } : prev));
    }, []);

    const setNotifyNewPos = useCallback(
        (v: boolean) => {
            dismissStatus();
            setNotifyNewPosRaw(v);
        },
        [dismissStatus],
    );
    const setNotifySupportChange = useCallback(
        (v: boolean) => {
            dismissStatus();
            setNotifySupportChangeRaw(v);
        },
        [dismissStatus],
    );
    const setNotifySummaryChange = useCallback(
        (v: boolean) => {
            dismissStatus();
            setNotifySummaryChangeRaw(v);
        },
        [dismissStatus],
    );
    const setCadence = useCallback(
        (v: CadenceValue) => {
            dismissStatus();
            setCadenceRaw(v);
        },
        [dismissStatus],
    );

    const loadDefaults = useCallback(async () => {
        setLoading(true);
        setLoadError(null);
        try {
            const data = await apiClient.get<OrgDefaultsPayload>(Routes.orgNotificationDefaults());
            if (data.notify_on_new_position_default !== undefined)
                setNotifyNewPosRaw(data.notify_on_new_position_default);
            if (data.notify_on_support_change_default !== undefined)
                setNotifySupportChangeRaw(data.notify_on_support_change_default);
            if (data.notify_on_summary_change_default !== undefined)
                setNotifySummaryChangeRaw(data.notify_on_summary_change_default);
            if (data.org_position_cadence_default !== undefined) setCadenceRaw(data.org_position_cadence_default);
        } catch {
            setLoadError("Couldn't load organization defaults.");
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        void loadDefaults();
    }, [loadDefaults]);

    useEffect(() => {
        if (saveState.kind === "saved") {
            AccessibilityInfo.announceForAccessibility(PARITY_COPY.notifications.saved);
            const timer = setTimeout(() => setSaveState({ kind: "idle" }), SAVED_VISIBLE_MS);
            return () => clearTimeout(timer);
        }
        if (saveState.kind === "error") {
            AccessibilityInfo.announceForAccessibility(saveState.message);
        }
        return undefined;
    }, [saveState]);

    const save = useCallback(async () => {
        if (inFlight.current) return;
        inFlight.current = true;
        setSaveState({ kind: "saving" });
        try {
            await apiClient.patch(Routes.orgNotificationDefaults(), {
                notify_on_new_position_default: notifyNewPos,
                notify_on_support_change_default: notifySupportChange,
                notify_on_summary_change_default: notifySummaryChange,
                org_position_cadence_default: cadence,
            });
            setSaveState({ kind: "saved" });
        } catch (e) {
            setSaveState({ kind: "error", message: saveErrorMessage(e) });
        } finally {
            inFlight.current = false;
        }
    }, [notifyNewPos, notifySupportChange, notifySummaryChange, cadence]);

    return {
        loading,
        loadError,
        saveState,
        save,
        notifyNewPos,
        setNotifyNewPos,
        notifySupportChange,
        setNotifySupportChange,
        notifySummaryChange,
        setNotifySummaryChange,
        cadence,
        setCadence,
    };
}

type OrgDefaultsForm = ReturnType<typeof useOrgDefaultsForm>;

// @lat: [[org-notification-cascade-and-defaults#Mobile: NotificationPrefsScreen organization position updates card]]
function OrgDefaultsCard({ form }: { form: OrgDefaultsForm }) {
    const { colorScheme } = useTheme();
    const {
        loading,
        loadError,
        notifyNewPos,
        setNotifyNewPos,
        notifySupportChange,
        setNotifySupportChange,
        notifySummaryChange,
        setNotifySummaryChange,
        cadence,
        setCadence,
    } = form;

    return (
        <View className="px-4 pt-4">
            <Card testID="org-defaults-card">
                <Text
                    testID="org-defaults-card-title"
                    className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    {PARITY_COPY.orgNotifications.panelTitle}
                </Text>
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {PARITY_COPY.orgNotifications.panelDescription}
                </Text>

                {loading ? (
                    <ActivityIndicator
                        testID="org-defaults-loading"
                        accessibilityLabel="Loading organization defaults"
                    />
                ) : null}

                {loadError ? (
                    <Text
                        testID="org-defaults-error"
                        accessibilityRole="alert"
                        className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                    >
                        {loadError}
                    </Text>
                ) : null}

                {!loading ? (
                    <>
                        {/* @lat: [[org-notification-cascade-and-defaults#Mobile: NotificationPrefsScreen organization position updates card]] */}
                        <Text className="text-xs font-open-sans-semibold tracking-widest uppercase text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.orgNotifications.defaultsEventsLabel}
                        </Text>

                        <PreferenceToggle
                            name="notify_on_new_position_default"
                            label={PARITY_COPY.orgNotifications.eventNewPosition}
                            description="Notify by default when Sway records a new position from this organization."
                            value={notifyNewPos}
                            onValueChange={setNotifyNewPos}
                            testID="org-default-toggle-new-position"
                        />
                        <PreferenceToggle
                            name="notify_on_support_change_default"
                            label={PARITY_COPY.orgNotifications.eventSupportChange}
                            description="Notify by default when this org changes its for/against position."
                            value={notifySupportChange}
                            onValueChange={setNotifySupportChange}
                            testID="org-default-toggle-support-change"
                        />
                        <PreferenceToggle
                            name="notify_on_summary_change_default"
                            label={PARITY_COPY.orgNotifications.eventSummaryChange}
                            description="Notify by default when this org updates its position summary."
                            value={notifySummaryChange}
                            onValueChange={setNotifySummaryChange}
                            testID="org-default-toggle-summary-change"
                        />

                        <Text className="text-xs font-open-sans-semibold tracking-widest uppercase text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.orgNotifications.defaultsCadenceLabel}
                        </Text>
                        <View
                            className="flex-row gap-2 flex-wrap"
                            testID="org-defaults-cadence-picker"
                            accessibilityLabel="Default delivery cadence"
                        >
                            {CADENCE_OPTIONS.map((opt) => {
                                const isSelected = cadence === opt.value;
                                return (
                                    <RNPressable
                                        key={opt.value}
                                        testID={`org-defaults-cadence-${opt.value}`}
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
                    </>
                ) : null}
            </Card>
        </View>
    );
}

// @lat: [[test-push-device-targeting#Why NotificationPrefsScreen test mocks DeviceRegistrationContext]]
function PushTab() {
    const [permStatus, setPermStatus] = useState<"loading" | "granted" | "denied" | "undetermined">("loading");
    const [callerToken, setCallerToken] = useState<string | null>(null);
    const [postResult, setPostResult] = useState<"idle" | "sent" | "error">("idle");
    const { registrationStatus, deviceToken, registerPushToken } = useDeviceRegistration();

    const refreshPerm = useCallback(async () => {
        try {
            const r = await Notifications.getPermissionsAsync();
            if (r.status === "granted") {
                setPermStatus("granted");
                // @lat: [[test-push-device-targeting#Mobile: only usePushToken sends the token to the server]]
                try {
                    const t = await Notifications.getDevicePushTokenAsync();
                    setCallerToken(t.data);
                } catch {
                    setCallerToken(null);
                }
            } else if (r.status === "denied" && !r.canAskAgain) {
                setPermStatus("denied");
            } else {
                setPermStatus("undetermined");
            }
        } catch {
            setPermStatus("undetermined");
        }
    }, []);

    useEffect(() => {
        void refreshPerm();
    }, [refreshPerm]);

    const onEnable = useCallback(async () => {
        try {
            await Notifications.requestPermissionsAsync();
        } catch {}
        await refreshPerm();
        await registerPushToken?.();
    }, [refreshPerm, registerPushToken]);

    const onOpenSettings = useCallback(() => {
        Linking.openSettings();
    }, []);

    const tokenToSend = callerToken ?? deviceToken;

    const onTest = useCallback(async () => {
        if (!tokenToSend) {
            setPostResult("error");
            return;
        }
        try {
            await apiClient.post(Routes.testPush(), { push_token: tokenToSend });
            setPostResult("sent");
        } catch {
            setPostResult("error");
        }
    }, [tokenToSend]);

    const status: PushUiStatus = (() => {
        if (permStatus === "loading") return "loading";
        if (permStatus === "denied") return "denied";
        if (permStatus === "undetermined") return "undetermined";
        if (postResult === "sent") return "test-sent";
        if (postResult === "error") return "test-send-error";
        return registrationStatus === "registered" ? "granted-and-registered" : "granted-pending-registration";
    })();

    return (
        <View className="px-4 pt-4">
            <Card testID="push-tab-section">
                <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {PARITY_COPY.notifications.push.title}
                </Text>

                {status === "loading" ? (
                    <ActivityIndicator accessibilityLabel="Loading push permission status" />
                ) : null}

                {status === "undetermined" ? (
                    <Pressable
                        testID="push-enable-cta"
                        onPress={onEnable}
                        accessibilityLabel={PARITY_COPY.notifications.push.enableCta}
                    >
                        <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.notifications.push.enableCta}
                        </Text>
                    </Pressable>
                ) : null}

                {status === "denied" ? (
                    <>
                        <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark">
                            {PARITY_COPY.notifications.push.deniedCopy}
                        </Text>
                        <Pressable
                            testID="push-settings-cta"
                            variant="outline"
                            onPress={onOpenSettings}
                            accessibilityLabel="Open device Settings to enable push notifications"
                        >
                            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.notifications.push.settingsCta}
                            </Text>
                        </Pressable>
                    </>
                ) : null}

                {status === "granted-pending-registration" ? (
                    <Text
                        testID="push-registering-status"
                        className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {PARITY_COPY.notifications.push.registeringCopy}
                    </Text>
                ) : null}

                {status === "granted-and-registered" || status === "test-sent" || status === "test-send-error" ? (
                    <>
                        {status === "test-sent" ? (
                            <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.notifications.push.testSentCopy}
                            </Text>
                        ) : (
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                {PARITY_COPY.notifications.push.subscribedCopy}
                            </Text>
                        )}
                        {status === "test-send-error" ? (
                            <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark">
                                {PARITY_COPY.notifications.push.testSendErrorCopy}
                            </Text>
                        ) : null}
                        <Pressable
                            testID="push-test-cta"
                            variant="outline"
                            onPress={onTest}
                            accessibilityLabel="Send a test push notification to this device"
                        >
                            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.notifications.push.testCta}
                            </Text>
                        </Pressable>
                    </>
                ) : null}
            </Card>
        </View>
    );
}

export default function NotificationPrefsScreen() {
    const { prefs, loading, error: hookError, toggle } = useNotificationPrefs();
    const orgForm = useOrgDefaultsForm();
    const insets = useSafeAreaInsets();
    const { saveState } = orgForm;
    const saving = saveState.kind === "saving";
    const [error, setError] = useState<string | null>(null);
    const [pending, setPending] = useState<NotificationPrefKey | null>(null);

    const onToggle = async (key: NotificationPrefKey, next: boolean) => {
        setError(null);
        setPending(key);
        try {
            await toggle(key, next);
        } catch (e) {
            setError(e instanceof Error ? e.message : PARITY_COPY.notifications.errorSave);
        } finally {
            setPending(null);
        }
    };

    const displayedError = error ?? (hookError ? PARITY_COPY.notifications.errorSave : null);

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark">
            <ScrollView
                className="flex-1"
                contentInsetAdjustmentBehavior="automatic"
                testID="notification-prefs-screen"
            >
                <View className="p-6">
                    <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {PARITY_COPY.notifications.title}
                    </Text>
                    <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mt-2">
                        {PARITY_COPY.notifications.lead}
                    </Text>
                </View>

                {loading ? (
                    <View className="p-6">
                        <ActivityIndicator accessibilityLabel="Loading preferences" />
                    </View>
                ) : null}

                <View className="px-4">
                    <Card testID="notification-prefs-card">
                        {TOGGLE_ROWS.map((row) => {
                            const pref = prefs.find((p) => p.key === row.key);
                            return (
                                <PreferenceToggle
                                    key={row.key}
                                    name={row.key}
                                    label={row.label}
                                    description={row.description}
                                    value={pref?.enabled ?? row.defaultEnabled}
                                    disabled={pending === row.key}
                                    onValueChange={(next) => onToggle(row.key, next)}
                                />
                            );
                        })}
                    </Card>
                </View>

                <PushTab />

                <OrgDefaultsCard form={orgForm} />

                {displayedError ? (
                    <Text
                        testID="notification-prefs-error"
                        className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark p-6"
                    >
                        {displayedError}
                    </Text>
                ) : null}
            </ScrollView>

            <View
                testID="notification-prefs-footer"
                className="px-4 pt-3 gap-2 border-t border-border-strong-light dark:border-border-strong-dark bg-dominant-light dark:bg-dominant-dark"
                style={{ paddingBottom: Math.max(insets.bottom, 12) }}
            >
                {saveState.kind === "saved" ? (
                    <View testID="notification-prefs-save-status" accessibilityLiveRegion="polite">
                        <Text className="text-sm font-open-sans-semibold text-success-light dark:text-success-dark">
                            {PARITY_COPY.notifications.saved}
                        </Text>
                    </View>
                ) : null}
                {saveState.kind === "error" ? (
                    <View
                        testID="notification-prefs-save-error"
                        accessibilityRole="alert"
                        accessibilityLiveRegion="assertive"
                    >
                        <Text className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark">
                            {saveState.message}
                        </Text>
                    </View>
                ) : null}
                <Pressable
                    testID="org-defaults-save"
                    accessibilityLabel={PARITY_COPY.orgNotifications.savePreferences}
                    accessibilityState={{ busy: saving }}
                    onPress={orgForm.save}
                    disabled={saving || orgForm.loading || orgForm.loadError !== null}
                    className="min-h-[44px]"
                >
                    <Text className="text-sm font-open-sans-semibold text-white">
                        {saving ? PARITY_COPY.notifications.saving : PARITY_COPY.orgNotifications.savePreferences}
                    </Text>
                </Pressable>
            </View>
        </View>
    );
}
