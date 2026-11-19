// @lat: [[mobile-admin-area#The user address changes screen]]
import React from "react";
import { ActivityIndicator, RefreshControl, ScrollView, Text, View } from "react-native";

import { Card } from "../../components/ui/Card";
import { EmptyState } from "../../components/ui/EmptyState";
import { useUserAddressChanges, type UserAddressChangeRow } from "../../hooks/admin/useUserAddressChanges";

const pluralize = (count: number, singular: string, plural: string) => `${count} ${count === 1 ? singular : plural}`;

const formatIdList = (ids: number[]) => (ids.length === 0 ? "none" : ids.join(", "));

const formatLocaleList = (names: string[], ids: number[]) => (names.length > 0 ? names.join(", ") : formatIdList(ids));

const formatPriorVotes = (row: UserAddressChangeRow) => {
    const base = pluralize(row.prior_vote_count, "vote", "votes");
    return row.prior_voted_bill_ids.length === 0 ? base : `${base} (Bills: ${row.prior_voted_bill_ids.join(", ")})`;
};

const Flag = ({ label }: { label: string }) => (
    <Text className="rounded-full border border-border-soft-light dark:border-border-soft-dark px-2 py-0.5 text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
        {label}
    </Text>
);

const Detail = ({ label, value }: { label: string; value: string }) => (
    <View>
        <Text className="text-xs font-open-sans-semibold text-foreground-light dark:text-foreground-dark">{label}</Text>
        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {value}
        </Text>
    </View>
);

const ChangeCard = ({ row }: { row: UserAddressChangeRow }) => (
    <Card testID={`admin-user-address-change-${row.id}`} className="mx-4 mb-3">
        <View className="flex-row flex-wrap items-center gap-2">
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {`User #${row.user_id}`}
            </Text>
            <Flag label={`${pluralize(row.user_switch_count, "switch", "switches")} total`} />
            {row.user_switch_count > 1 ? <Flag label="Repeat switcher" /> : null}
            {row.cross_district ? <Flag label="Cross-district" /> : null}
            {row.cross_sway_locale ? <Flag label="Cross-locale" /> : null}
            {row.voted_before_switch ? <Flag label="Voted before switch" /> : null}
        </View>
        <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {row.created_at}
        </Text>
        <Detail label="Address" value={`Address #${row.previous_address_id} -> #${row.new_address_id}`} />
        <Detail
            label="Locales"
            value={`${formatLocaleList(row.previous_sway_locale_names, row.previous_sway_locale_ids)} -> ${formatLocaleList(row.new_sway_locale_names, row.new_sway_locale_ids)}`}
        />
        <Detail
            label="Districts"
            value={`${formatIdList(row.deactivated_district_ids)} -> ${formatIdList(row.activated_district_ids)}`}
        />
        <Detail
            label="Legislators"
            value={`${formatIdList(row.deactivated_legislator_ids)} -> ${formatIdList(row.activated_legislator_ids)}`}
        />
        <Detail label="Prior votes" value={formatPriorVotes(row)} />
    </Card>
);

export default function UserAddressChangesScreen() {
    const { userAddressChanges, loading, error, refresh } = useUserAddressChanges();

    return (
        <ScrollView
            testID="admin-user-address-changes-screen"
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
            contentContainerStyle={{ paddingBottom: 24 }}
            refreshControl={
                <RefreshControl
                    refreshing={loading && userAddressChanges !== null}
                    onRefresh={() => {
                        void refresh();
                    }}
                    accessibilityLabel="Pull to refresh the address changes"
                />
            }
        >
            <View className="px-4 pt-6 pb-4">
                <Text
                    accessibilityRole="header"
                    className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Address Changes
                </Text>
                <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    Audit trail of user address switches across districts and locales, shown by identifier and counts
                    only, with no street and no coordinates.
                </Text>
            </View>
            {error ? (
                <EmptyState title={error.message} testID="admin-user-address-changes-error" />
            ) : userAddressChanges === null ? (
                <ActivityIndicator testID="admin-user-address-changes-loading" className="py-12" />
            ) : userAddressChanges.length === 0 ? (
                <EmptyState title="No user address switches have been recorded." />
            ) : (
                userAddressChanges.map((row) => <ChangeCard key={row.id} row={row} />)
            )}
        </ScrollView>
    );
}
