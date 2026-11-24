// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";

import PasteSummarySection from "../../../../components/admin/billCreator/PasteSummarySection";
import SummaryGenerationSection from "../../../../components/admin/billCreator/SummaryGenerationSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";

export default function SummaryTab({ billId, data, refresh }: BillCreatorTabProps) {
    return (
        <>
            <SummaryGenerationSection key={billId ?? "new"} billId={billId} data={data} refresh={refresh} />
            <PasteSummarySection key={billId ?? "new"} billId={billId} refresh={refresh} />
        </>
    );
}
