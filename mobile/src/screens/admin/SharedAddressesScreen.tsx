// @lat: [[mobile-admin-area#The shared addresses screen]]
import React from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { EmptyState } from "../../components/ui/EmptyState";
import { ListRow } from "../../components/ui/ListRow";
import { useSharedAddresses } from "../../hooks/admin/useSharedAddresses";

const pluralize = (count: number, singular: string, plural: string) => `${count} ${count === 1 ? singular : plural}`;

export default function SharedAddressesScreen() {
    const { sharedAddresses, loading, error, refresh } = useSharedAddresses();

    return (
        <ScrollView
            testID="admin-shared-addresses-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && sharedAddresses !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the shared addresses"
                />
            }
        >
            <View className="px-4 pt-6 pb-2">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Shared Addresses
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Addresses more than one registered user has given, shown by count only. A few people at one address
                    is a normal household; a much larger count is worth a look.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-shared-addresses-error" />
            ) : sharedAddresses === null ? (
                <ActivityIndicator testID="admin-shared-addresses-loading" className="py-12" />
            ) : sharedAddresses.length === 0 ? (
                <EmptyState title="No address has been given by more than one registered user." />
            ) : (
                sharedAddresses.map((row) => (
                    <ListRow
                        key={row.address_ids.join("-")}
                        label={`Address ID ${row.address_ids.join(", ")}`}
                        rightSlot={
                            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {pluralize(row.user_count, "user", "users")}
                            </Text>
                        }
                    />
                ))
            )}
        </ScrollView>
    );
}
