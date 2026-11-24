// @lat: [[mobile-bill-creator#The tabs]]
import React from "react";

import NewsArticlesSection from "../../../../components/admin/billCreator/NewsArticlesSection";
import PasteSummarySection from "../../../../components/admin/billCreator/PasteSummarySection";
import SummaryGenerationSection from "../../../../components/admin/billCreator/SummaryGenerationSection";
import SummaryRevisionsSection from "../../../../components/admin/billCreator/SummaryRevisionsSection";
import SummarySourcesSection from "../../../../components/admin/billCreator/SummarySourcesSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";

export default function SummaryTab({ billId, data, refresh, onReviewDraft }: BillCreatorTabProps) {
    return (
        <>
            <SummaryGenerationSection
                key={`generation-${billId ?? "new"}`}
                billId={billId}
                data={data}
                refresh={refresh}
            />
            <SummarySourcesSection key={`sources-${billId ?? "new"}`} billId={billId} data={data} refresh={refresh} />
            <PasteSummarySection key={`paste-${billId ?? "new"}`} billId={billId} refresh={refresh} />
            <SummaryRevisionsSection
                key={`revisions-${billId ?? "new"}`}
                billId={billId}
                data={data}
                refresh={refresh}
                onReviewDraft={onReviewDraft}
            />
            <NewsArticlesSection key={`news-${billId ?? "new"}`} billId={billId} data={data} refresh={refresh} />
        </>
    );
}
