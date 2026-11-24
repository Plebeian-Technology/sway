// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";

import PipelineProgressSection from "../../../../components/admin/billCreator/PipelineProgressSection";
import PipelineStagesSection from "../../../../components/admin/billCreator/PipelineStagesSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";

export default function PipelineTab({ billId, data, refresh }: BillCreatorTabProps) {
    return (
        <>
            <PipelineStagesSection key={billId} billId={billId} data={data} refresh={refresh} />
            <PipelineProgressSection billId={billId} data={data} refresh={refresh} />
        </>
    );
}
