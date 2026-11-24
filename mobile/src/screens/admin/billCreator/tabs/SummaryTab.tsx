// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";

import SummaryGenerationSection from "../../../../components/admin/billCreator/SummaryGenerationSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";

export default function SummaryTab({ billId, data, refresh }: BillCreatorTabProps) {
    return <SummaryGenerationSection key={billId ?? "new"} billId={billId} data={data} refresh={refresh} />;
}
