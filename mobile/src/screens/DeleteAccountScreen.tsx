// @lat: [[mobile-profile-and-delete-account-screens#DeleteAccountScreen]]
import React, { useState } from "react";
import { Alert, ScrollView, Text, View } from "react-native";

import { apiClient } from "../api/client";
import { Routes } from "../api/routes";
import { DestructiveSheet } from "../components/DestructiveSheet";
import { useSession } from "../hooks/useSession";
import { useUserProfile } from "../hooks/useUserProfile";
import { Pressable } from "@/components/ui/Pressable";

export default function DeleteAccountScreen() {
    const { user } = useUserProfile();
    const { signOut } = useSession();

    const [open, setOpen] = useState(false);
    const [busy, setBusy] = useState(false);

    const onConfirm = async () => {
        if (!user?.id) {
            Alert.alert("Not signed in", "Sign in again before deleting your account.");
            setOpen(false);
            return;
        }
        setBusy(true);
        try {
            await apiClient.delete(Routes.userDelete(user.id));
            await signOut({ skipServerRevoke: true });
            setOpen(false);
        } catch (e) {
            setOpen(false);
            Alert.alert("Could not delete account", e instanceof Error ? e.message : String(e));
        } finally {
            setBusy(false);
        }
    };

    return (
        <ScrollView
            className="flex-1 bg-dominant-light dark:bg-dominant-dark p-6"
            contentInsetAdjustmentBehavior="automatic"
            testID="delete-account-screen"
        >
            <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-2">
                Delete account
            </Text>

            {/* @lat: [[mobile-profile-and-delete-account-screens#DeleteAccountScreen]] */}
            <Text className="text-base font-open-sans-light text-foreground-light dark:text-foreground-dark mb-6">
                This permanently removes your votes, profile, and history. This cannot be undone.
            </Text>

            <View className="mb-6">
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    If you&apos;d rather take a break instead, sign out from the Profile screen — your data stays intact
                    and you can sign back in any time.
                </Text>
            </View>

            <Pressable
                onPress={() => setOpen(true)}
                variant="destructive"
                accessibilityRole="button"
                accessibilityLabel="Delete Account"
                testID="btn-open-delete-account-sheet"
            >
                <Text className="text-center text-sm font-open-sans-semibold text-white">Delete Account</Text>
            </Pressable>

            <DestructiveSheet
                visible={open}
                title="Delete account"
                body="This permanently removes your votes, profile, and history. This cannot be undone."
                actionLabel="Delete Account"
                onConfirm={onConfirm}
                onDismiss={() => setOpen(false)}
                busy={busy}
                testID="sheet-delete-account"
            />
        </ScrollView>
    );
}
