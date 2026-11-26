// @lat: [[mobile-admin-area#The locales screen]]
import React, { useState } from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { Routes } from "../../api/routes";
import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { FormField } from "../../components/ui/FormField";
import { Pressable } from "../../components/ui/Pressable";
import { useAdminLocales, type AdminLocaleRow } from "../../hooks/admin/useAdminLocales";
import { useAdminMutation } from "../../hooks/admin/useAdminMutation";

const asText = (value: string | number | null) => (value === null ? "" : String(value));

const hasSampleAddress = (row: AdminLocaleRow) =>
    row.sample_street !== null &&
    row.sample_postal_code !== null &&
    row.sample_latitude !== null &&
    row.sample_longitude !== null;

const userCountLabel = (count: number) => `${count.toLocaleString()} ${count === 1 ? "user" : "users"}`;

const SampleAddressForm = ({ row, onSaved }: { row: AdminLocaleRow; onSaved: () => void }) => {
    const [street, setStreet] = useState(asText(row.sample_street));
    const [postalCode, setPostalCode] = useState(asText(row.sample_postal_code));
    const [latitude, setLatitude] = useState(asText(row.sample_latitude));
    const [longitude, setLongitude] = useState(asText(row.sample_longitude));
    const { run, loading, errorMessage } = useAdminMutation("patch", Routes.adminLocale(row.id));

    const save = async () => {
        const saved = await run({
            sway_locale: {
                sample_street: street,
                sample_postal_code: postalCode,
                sample_latitude: latitude,
                sample_longitude: longitude,
            },
        });
        if (saved !== undefined) onSaved();
    };

    return (
        <View className="mt-3">
            <Text className="mb-3 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                The address a stand-in development account signs in with. Empty on every locale but the demo one.
            </Text>
            <FormField
                testID={`admin-locale-${row.id}-street`}
                label="Street"
                value={street}
                onChangeText={setStreet}
                disabled={loading}
            />
            <FormField
                testID={`admin-locale-${row.id}-postal-code`}
                label="Postal code"
                value={postalCode}
                onChangeText={setPostalCode}
                disabled={loading}
            />
            <FormField
                testID={`admin-locale-${row.id}-latitude`}
                label="Latitude"
                value={latitude}
                onChangeText={setLatitude}
                keyboardType="numbers-and-punctuation"
                disabled={loading}
            />
            <FormField
                testID={`admin-locale-${row.id}-longitude`}
                label="Longitude"
                value={longitude}
                onChangeText={setLongitude}
                keyboardType="numbers-and-punctuation"
                disabled={loading}
            />
            {errorMessage ? (
                <Text
                    testID={`admin-locale-${row.id}-error`}
                    className="mb-3 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {errorMessage}
                </Text>
            ) : null}
            <Pressable
                testID={`admin-locale-${row.id}-save`}
                variant="default"
                disabled={loading}
                onPress={() => void save()}
                accessibilityLabel={`Save the sample address of ${row.label}`}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Saving..." : "Save sample address"}
                </Text>
            </Pressable>
        </View>
    );
};

const LocaleRow = ({ row, onSaved }: { row: AdminLocaleRow; onSaved: () => void }) => {
    const [editing, setEditing] = useState(false);

    return (
        <View testID={`admin-locale-${row.id}`} className="py-2">
            <View className="flex-row items-center justify-between gap-3">
                <View className="flex-1">
                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {row.label}
                    </Text>
                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        {userCountLabel(row.user_count)}
                    </Text>
                </View>
                <Pressable
                    testID={`admin-locale-${row.id}-toggle`}
                    variant="outline"
                    accessibilityState={{ expanded: editing }}
                    onPress={() => setEditing((open) => !open)}
                >
                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {hasSampleAddress(row) ? "Sample address" : "Add sample address"}
                    </Text>
                </Pressable>
            </View>
            {editing ? (
                <SampleAddressForm
                    row={row}
                    onSaved={() => {
                        setEditing(false);
                        onSaved();
                    }}
                />
            ) : null}
        </View>
    );
};

export default function LocalesScreen() {
    const { data, loading, error, refresh } = useAdminLocales();

    return (
        <ScrollView
            testID="admin-locales-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            keyboardShouldPersistTaps="handled"
            refreshControl={
                <RefreshControl
                    refreshing={loading && data !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the locales"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Locales
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Registered users per locale. City and state locales are created automatically from each registered
                    address, so this is every place Sway has a registration, not only the supported ones.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-locales-error" />
            ) : data === null ? (
                <ActivityIndicator testID="admin-locales-loading" className="py-12" />
            ) : (
                data.tiers.map((tier) => (
                    <Card key={tier.key} testID={`admin-locales-tier-${tier.key}`} className="mx-4 mb-3">
                        <Text className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {tier.label}
                        </Text>
                        {tier.locales.length === 0 ? (
                            <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                                No locales yet.
                            </Text>
                        ) : (
                            tier.locales.map((row) => (
                                <LocaleRow
                                    key={row.id}
                                    row={row}
                                    onSaved={() => {
                                        void refresh();
                                    }}
                                />
                            ))
                        )}
                    </Card>
                ))
            )}
        </ScrollView>
    );
}
