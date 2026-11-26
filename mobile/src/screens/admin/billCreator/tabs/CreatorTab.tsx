// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import BillFieldsSection, { type CreatorBill } from "../../../../components/admin/billCreator/BillFieldsSection";
import type { EvidenceArticle } from "../../../../components/admin/billCreator/NewsEvidenceControls";
import LegislatorVotesSection, {
    type CreatorLegislatorVote,
    type CreatorVoteLegislator,
} from "../../../../components/admin/billCreator/LegislatorVotesSection";
import OrganizationsSection from "../../../../components/admin/billCreator/OrganizationsSection";
import SummaryAudioSection, {
    type CreatorBillAudio,
} from "../../../../components/admin/billCreator/SummaryAudioSection";
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
                newsArticles={(data.news_articles ?? []) as EvidenceArticle[]}
                onSaved={(saved) => {
                    if (billId === null && saved.id !== null) {
                        navigation.setParams({ billId: saved.id });
                    } else {
                        void refresh();
                    }
                }}
            />
            <SummaryAudioSection billId={billId} bill={data.bill as CreatorBillAudio | undefined} />
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
