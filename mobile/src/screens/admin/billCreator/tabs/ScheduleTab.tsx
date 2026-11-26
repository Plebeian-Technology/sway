// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";

import BillScheduleSection, {
    type ScheduleBill,
    type SchedulePickerBill,
} from "../../../../components/admin/billCreator/BillScheduleSection";
import ScheduledBillsSection from "../../../../components/admin/billCreator/ScheduledBillsSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";
import type { AdminStackParamList } from "../../../../navigation/types";

export default function ScheduleTab({ billId, data, refresh }: BillCreatorTabProps) {
    const navigation = useNavigation<NativeStackNavigationProp<AdminStackParamList, "AdminBillCreator">>();
    const bills = (data.bills ?? []) as SchedulePickerBill[];

    return (
        <>
            <BillScheduleSection
                key={billId}
                billId={billId}
                bill={data.bill as ScheduleBill | undefined}
                bills={bills}
                onChanged={() => void refresh()}
            />
            <ScheduledBillsSection
                bills={bills}
                selectedBillId={billId}
                onSelectBill={(bill) => navigation.setParams({ billId: bill.id })}
            />
        </>
    );
}
