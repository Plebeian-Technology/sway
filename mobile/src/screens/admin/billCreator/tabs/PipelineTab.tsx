// @lat: [[mobile-bill-creator#The tabs]]
import React, { useEffect, useState } from "react";

import ActivityLogSection, { type ActivityLogEntry } from "../../../../components/admin/billCreator/ActivityLogSection";
import FetchedBillsSection, {
    type FetchedBillsRow,
} from "../../../../components/admin/billCreator/FetchedBillsSection";
import PerBillGridSection, { type PerBillGridRun } from "../../../../components/admin/billCreator/PerBillGridSection";
import PipelineCleanupSection from "../../../../components/admin/billCreator/PipelineCleanupSection";
import PipelineProgressSection from "../../../../components/admin/billCreator/PipelineProgressSection";
import PipelineRunActionsSection from "../../../../components/admin/billCreator/PipelineRunActionsSection";
import PipelineStagesSection from "../../../../components/admin/billCreator/PipelineStagesSection";
import ResourceCacheSection, {
    type ResourceCacheRow,
} from "../../../../components/admin/billCreator/ResourceCacheSection";
import RunSelectorSection, {
    type RecentPipelineRun,
} from "../../../../components/admin/billCreator/RunSelectorSection";
import SendingServicesSection from "../../../../components/admin/billCreator/SendingServicesSection";
import type { BillCreatorTabProps } from "../../../../hooks/admin/useBillCreator";
import { usePinnedPipelineRun } from "../../../../hooks/admin/usePinnedPipelineRun";

export default function PipelineTab({ billId, data, refresh }: BillCreatorTabProps) {
    const [pinnedRunId, setPinnedRunId] = useState<number | null>(null);
    const pinnedRun = usePinnedPipelineRun(billId, pinnedRunId);

    useEffect(() => setPinnedRunId(null), [billId]);

    const shownData =
        pinnedRunId !== null && pinnedRun.data
            ? {
                  ...data,
                  legislation_pipeline_run: pinnedRun.data.legislation_pipeline_run,
                  recent_pipeline_runs: pinnedRun.data.recent_pipeline_runs,
              }
            : data;
    const shownRefresh = pinnedRunId === null ? refresh : pinnedRun.refresh;
    const startedNewRun = async () => {
        setPinnedRunId(null);
        await refresh();
    };

    const refreshAfterCleanup = async () => {
        await refresh();
        if (pinnedRunId !== null) await pinnedRun.refresh();
    };

    return (
        <>
            <PipelineStagesSection key={billId} billId={billId} data={data} refresh={refresh} />
            <RunSelectorSection
                runs={(shownData.recent_pipeline_runs ?? []) as RecentPipelineRun[]}
                currentRunId={(shownData.legislation_pipeline_run as { id?: number } | null)?.id ?? null}
                pinned={pinnedRunId !== null}
                onPick={setPinnedRunId}
            />
            <PipelineRunActionsSection billId={billId} data={shownData} refresh={startedNewRun} />
            <PipelineProgressSection billId={billId} data={shownData} refresh={shownRefresh} />
            <PerBillGridSection
                run={(shownData.legislation_pipeline_run ?? null) as PerBillGridRun | null}
                currentBillExternalId={data.bill?.external_id ?? ""}
            />
            <PipelineCleanupSection billId={billId} data={shownData} refresh={refreshAfterCleanup} />
            <SendingServicesSection billId={billId} data={data} refresh={refresh} />
            <ResourceCacheSection mirrors={(data.bill_artifact_mirrors ?? []) as ResourceCacheRow[]} />
            <FetchedBillsSection rows={(data.fetched_bills ?? []) as FetchedBillsRow[]} />
            <ActivityLogSection
                key={`activity-log-${billId}`}
                billId={billId}
                entries={(data.activity_log_entries ?? []) as ActivityLogEntry[]}
                nextCursor={(data.activity_log_next_cursor ?? null) as string | null}
                hasMore={(data.activity_log_has_more ?? false) as boolean}
            />
        </>
    );
}
