// @lat: [[mobile-bill-creator#The bill picker]]
import React, { useMemo, useState } from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import { EmptyState } from "../../../components/ui/EmptyState";
import { FormField } from "../../../components/ui/FormField";
import { ListRow } from "../../../components/ui/ListRow";
import { useBillPicker } from "../../../hooks/admin/useBillPicker";
import type { AdminStackParamList } from "../../../navigation/types";

export default function BillPickerScreen() {
    const navigation = useNavigation<NativeStackNavigationProp<AdminStackParamList>>();
    const { bills, loading, error, refresh } = useBillPicker();
    const [query, setQuery] = useState("");

    const matches = useMemo(() => {
        const needle = query.trim().toLowerCase();
        if (!bills || needle === "") return bills;
        return bills.filter(
            (bill) => bill.external_id.toLowerCase().includes(needle) || bill.title.toLowerCase().includes(needle),
        );
    }, [bills, query]);

    return (
        <ScrollView
            testID="admin-bill-picker-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            keyboardShouldPersistTaps="handled"
            refreshControl={
                <RefreshControl
                    refreshing={loading && bills !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the bills"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Bill Creator
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-bill-picker-error" />
            ) : matches === null ? (
                <ActivityIndicator testID="admin-bill-picker-loading" className="py-12" />
            ) : (
                <>
                    <View className="px-4">
                        <FormField
                            testID="admin-bill-picker-search"
                            label="Search by bill number or title"
                            value={query}
                            onChangeText={setQuery}
                        />
                    </View>
                    <ListRow
                        testID="admin-bill-picker-new"
                        label="New bill"
                        onPress={() => navigation.navigate("AdminBillCreator", { billId: null })}
                    />
                    {matches.length === 0 ? (
                        <EmptyState title="No bills match your search." compact />
                    ) : (
                        matches.map((bill) => (
                            <ListRow
                                key={bill.id}
                                testID={`admin-bill-picker-bill-${bill.id}`}
                                label={bill.external_id}
                                description={bill.title}
                                onPress={() => navigation.navigate("AdminBillCreator", { billId: bill.id })}
                            />
                        ))
                    )}
                </>
            )}
        </ScrollView>
    );
}
