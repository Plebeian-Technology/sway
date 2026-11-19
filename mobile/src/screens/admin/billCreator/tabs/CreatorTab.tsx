// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import BillFieldsSection, { type CreatorBill } from "../../../../components/admin/billCreator/BillFieldsSection";
import LegislatorVotesSection, {
    type CreatorLegislatorVote,
    type CreatorVoteLegislator,
} from "../../../../components/admin/billCreator/LegislatorVotesSection";
import OrganizationsSection from "../../../../components/admin/billCreator/OrganizationsSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";
import type { AdminStackParamList } from "../../../../navigation/types";

export default function CreatorTab({ billId, data, refresh }: BillCreatorTabProps) {
    const navigation = useNavigation<NativeStackNavigationProp<AdminStackParamList, "AdminBillCreator">>();

    const legislators = (data.legislators ?? []) as CreatorVoteLegislator[];

    return (
        <>
            <BillFieldsSection
                billId={billId}
                bill={data.bill as CreatorBill | undefined}
                legislators={legislators}
                onSaved={(saved) => {
                    if (billId === null && saved.id !== null) {
                        navigation.setParams({ billId: saved.id });
                    } else {
                        void refresh();
                    }
                }}
            />
            <LegislatorVotesSection
                billId={billId}
                legislators={legislators}
                legislatorVotes={(data.legislator_votes ?? []) as CreatorLegislatorVote[]}
                refreshedAt={(data.legislator_votes_refreshed_at ?? null) as string | null}
                source={(data.legislator_votes_source ?? null) as string | null}
            />
            <OrganizationsSection billId={billId} data={data} refresh={refresh} />
        </>
    );
}
