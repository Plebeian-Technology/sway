// @lat: [[mobile-profile-and-delete-account-screens#ProfileScreen]]
import React, { useCallback, useState } from "react";
import { Alert, Pressable, ScrollView, Text, View } from "react-native";
import { DrawerActions, useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { Bell, KeyRound, LogOut, MapPin, SunMoon, Trash, UserRound, Users, UserX } from "lucide-react-native";

import BrandHeader from "../components/BrandHeader";
import { DestructiveSheet } from "../components/DestructiveSheet";
import { useSession } from "../hooks/useSession";
import { useUserProfile } from "../hooks/useUserProfile";
import { useThemeSync } from "../hooks/useThemeSync";
import { useTheme, type ThemeMode } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { shadowBold } from "../theme/effects";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { ProfileStackParamList } from "../navigation/types";

type Nav = NativeStackNavigationProp<ProfileStackParamList, "ProfileHub">;

const THEME_CYCLE: ThemeMode[] = ["auto", "light", "dark"];
const THEME_LABELS: Record<ThemeMode, string> = {
    auto: PARITY_COPY.theme.auto.label,
    light: PARITY_COPY.theme.light.label,
    dark: PARITY_COPY.theme.dark.label,
};

type RowIcon = React.ComponentType<{ size?: number; color?: string; strokeWidth?: number }>;

interface RowProps {
    label: string;
    onPress: () => void;
    icon: RowIcon;
    accessory?: string;
    destructive?: boolean;
    testID?: string;
    accessibilityLabel?: string;
}

// @lat: [[mobile-chrome-and-scroll-layout#Profile rows are grouped cards with icon tiles]]
function Row({ label, onPress, icon: Icon, accessory, destructive, testID, accessibilityLabel }: RowProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const tone = destructive ? t.destructive : t.primary;
    return (
        <Pressable
            onPress={onPress}
            accessibilityRole="button"
            accessibilityLabel={accessibilityLabel ?? label}
            testID={testID ?? `profile-row-${label.replace(/\s+/g, "-").toLowerCase()}`}
            className="min-h-[52px] flex-row items-center gap-3 px-4 py-2 border-b border-border-soft-light dark:border-border-soft-dark"
        >
            <View
                className="w-9 h-9 rounded-lg items-center justify-center bg-surface-3-light dark:bg-surface-3-dark"
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
            >
                <Icon size={20} color={tone} strokeWidth={2.25} />
            </View>
            <Text
                className={`flex-1 text-base font-open-sans-semibold ${
                    destructive
                        ? "text-destructive-light dark:text-destructive-dark"
                        : "text-foreground-light dark:text-foreground-dark"
                }`}
            >
                {label}
            </Text>
            {accessory ? (
                <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                    {accessory}
                </Text>
            ) : null}
            <Text className="text-xl font-open-sans-semibold text-accent-light dark:text-accent-dark">{"›"}</Text>
        </Pressable>
    );
}

export default function ProfileScreen() {
    const nav = useNavigation<Nav>();
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const { signOut, signOutAll } = useSession();
    const { user } = useUserProfile();
    const { mode, setMode } = useThemeSync();

    const [showSignOutAll, setShowSignOutAll] = useState(false);
    const [busy, setBusy] = useState(false);

    const onSignOut = useCallback(async () => {
        try {
            await signOut();
        } catch (e) {
            Alert.alert("Sign out incomplete", e instanceof Error ? e.message : String(e));
        }
    }, [signOut]);

    const onSignOutAllConfirm = useCallback(async () => {
        setBusy(true);
        try {
            await signOutAll();
            setShowSignOutAll(false);
        } catch (e) {
            setShowSignOutAll(false);
            Alert.alert("Sign out incomplete", e instanceof Error ? e.message : String(e));
        } finally {
            setBusy(false);
        }
    }, [signOutAll]);

    const onCycleTheme = useCallback(() => {
        const idx = THEME_CYCLE.indexOf(mode);
        const next = THEME_CYCLE[(idx + 1) % THEME_CYCLE.length];
        void setMode(next).catch(() => {});
    }, [mode, setMode]);

    const currentThemeLabel = THEME_LABELS[mode];
    const nextThemeLabel = THEME_LABELS[THEME_CYCLE[(THEME_CYCLE.indexOf(mode) + 1) % THEME_CYCLE.length]];

    return (
        <View className="flex-1 bg-dominant-light dark:bg-dominant-dark" testID="profile-screen">
            <BrandHeader
                title={PARITY_COPY.profile.title}
                testID="profile-brand-header"
                onMenuPress={() => nav.dispatch(DrawerActions.openDrawer())}
            />
            <ScrollView contentContainerStyle={{ paddingBottom: 32 }} testID="profile-scroll">
                {user?.full_name || user?.phone ? (
                    <View
                        testID="profile-identity"
                        className="mx-4 mt-4 flex-row items-center gap-3 rounded-card bg-card-light dark:bg-card-dark border border-border-soft-light dark:border-border-soft-dark px-4 py-3"
                        style={[shadowBold(colorScheme), { borderLeftWidth: 5, borderLeftColor: t.primary }]}
                    >
                        <View className="w-12 h-12 rounded-full items-center justify-center bg-accent-light dark:bg-accent-dark">
                            <UserRound size={26} color={t.primaryForeground} strokeWidth={2.25} />
                        </View>
                        <View className="flex-1">
                            {user?.full_name ? (
                                <Text className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    {user.full_name}
                                </Text>
                            ) : null}
                            {user?.phone ? (
                                <Text
                                    className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark"
                                    style={{ fontVariant: ["tabular-nums"] }}
                                >
                                    {user.phone}
                                </Text>
                            ) : null}
                        </View>
                    </View>
                ) : null}

                <Text
                    className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark px-5 pt-5 pb-2"
                    style={{ textTransform: "uppercase", letterSpacing: 1.6 }}
                >
                    Your account
                </Text>
                <View
                    className="mx-4 rounded-card overflow-hidden bg-card-light dark:bg-card-dark border border-border-soft-light dark:border-border-soft-dark"
                    style={shadowBold(colorScheme)}
                >
                    <Row
                        label={PARITY_COPY.profile.rows.address}
                        icon={MapPin}
                        onPress={() => nav.navigate("Address")}
                        testID="profile-row-address"
                    />
                    <Row
                        label={PARITY_COPY.profile.rows.memberships}
                        icon={Users}
                        onPress={() => nav.navigate("MembershipsList")}
                        testID="profile-my-memberships-row"
                    />
                    <Row
                        label={PARITY_COPY.profile.rows.notificationPrefs}
                        icon={Bell}
                        onPress={() => nav.navigate("NotificationPrefs")}
                        testID="profile-row-notification-preferences"
                    />
                    <Row
                        label={PARITY_COPY.profile.rows.passkeyManagement}
                        icon={KeyRound}
                        onPress={() => nav.navigate("PasskeyManagement")}
                        testID="profile-row-passkey-management"
                    />
                    <Row
                        label={PARITY_COPY.profile.rows.theme}
                        icon={SunMoon}
                        onPress={onCycleTheme}
                        accessory={currentThemeLabel}
                        testID="profile-row-theme"
                        accessibilityLabel={`Theme: ${currentThemeLabel}. Tap to switch to ${nextThemeLabel}.`}
                    />
                </View>

                <Text
                    className="text-xs font-open-sans-semibold text-accent-light dark:text-accent-dark px-5 pt-5 pb-2"
                    style={{ textTransform: "uppercase", letterSpacing: 1.6 }}
                >
                    Session
                </Text>
                <View
                    className="mx-4 rounded-card overflow-hidden bg-card-light dark:bg-card-dark border border-border-soft-light dark:border-border-soft-dark"
                    style={shadowBold(colorScheme)}
                >
                    <Row
                        label={PARITY_COPY.profile.rows.signOut}
                        icon={LogOut}
                        onPress={onSignOut}
                        testID="btn-sign-out"
                    />
                    <Row
                        label={PARITY_COPY.profile.rows.signOutAll}
                        icon={UserX}
                        onPress={() => setShowSignOutAll(true)}
                        destructive
                        testID="btn-sign-out-all"
                    />
                    <Row
                        label={PARITY_COPY.profile.rows.deleteAccount}
                        icon={Trash}
                        onPress={() => nav.navigate("DeleteAccount")}
                        destructive
                        testID="btn-delete-account"
                    />
                </View>
            </ScrollView>

            {/* @lat: [[mobile-profile-and-delete-account-screens#ProfileScreen]] */}
            <DestructiveSheet
                visible={showSignOutAll}
                title={PARITY_COPY.profile.account.signOutAllTitle}
                body={PARITY_COPY.profile.account.signOutAllBody}
                actionLabel={PARITY_COPY.profile.account.signOutAllAction}
                onConfirm={onSignOutAllConfirm}
                onDismiss={() => setShowSignOutAll(false)}
                busy={busy}
                testID="sheet-sign-out-all"
            />
        </View>
    );
}
