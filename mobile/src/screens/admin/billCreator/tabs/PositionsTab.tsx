// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";
import { Text, View } from "react-native";

import ClaimedAffiliationsSection from "../../../../components/admin/billCreator/ClaimedAffiliationsSection";
import DraftPositionsSection from "../../../../components/admin/billCreator/DraftPositionsSection";
import OrganizationsSection from "../../../../components/admin/billCreator/OrganizationsSection";
import { EmptyState } from "../../../../components/ui/EmptyState";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";

// @lat: [[mobile-bill-creator#Sections#The draft positions section#The organizations section on this tab]]
const organizationsKey = (billId: number, bill: unknown) => {
    const organizations = (bill as { organizations?: { id: number }[] } | undefined)?.organizations ?? [];
    const ids = organizations.map((organization) => organization.id).sort((a, b) => a - b);
    return `organizations-${billId}:${ids.length > 0 ? ids.join(",") : "none"}`;
};

export default function PositionsTab({ billId, data, refresh }: BillCreatorTabProps) {
    if (billId === null) {
        return (
            <EmptyState
                title="Save this bill to work through its testimony and organization positions."
                testID="admin-bill-creator-positions-no-bill"
            />
        );
    }

    return (
        <>
            <DraftPositionsSection key={`drafts-${billId}`} billId={billId} data={data} refresh={refresh} />
            <ClaimedAffiliationsSection key={`claimed-${billId}`} billId={billId} data={data} refresh={refresh} />
            <View className="px-4 mt-8 mb-2">
                <Text
                    accessibilityRole="header"
                    className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Supporting / opposing arguments
                </Text>
            </View>
            <OrganizationsSection
                key={organizationsKey(billId, data.bill)}
                billId={billId}
                data={data}
                refresh={refresh}
            />
        </>
    );
}
