// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import BillFieldsSection, {
    type CreatorBill,
    type CreatorLegislator,
} from "../../../../components/admin/billCreator/BillFieldsSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";
import type { AdminStackParamList } from "../../../../navigation/types";

export default function CreatorTab({ billId, data, refresh }: BillCreatorTabProps) {
    const navigation = useNavigation<NativeStackNavigationProp<AdminStackParamList, "AdminBillCreator">>();

    return (
        <BillFieldsSection
            billId={billId}
            bill={data.bill as CreatorBill | undefined}
            legislators={(data.legislators ?? []) as CreatorLegislator[]}
            onSaved={(saved) => {
                if (billId === null && saved.id !== null) {
                    navigation.setParams({ billId: saved.id });
                } else {
                    void refresh();
                }
            }}
        />
    );
}
