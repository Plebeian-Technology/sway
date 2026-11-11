// @lat: [[bill-creator-pipeline-llm-tab#Why this tab is one fixed-order column with a shared connection]]

import { usePage, usePoll } from "@inertiajs/react";
import { useEffect, useMemo } from "react";
import { sway } from "sway";
import ActivityLogPanel from "app/frontend/components/admin/creator/ActivityLogPanel";
import BillCreatorPipelineControls from "app/frontend/components/admin/creator/BillCreatorPipelineControls";
import { PHASE_52_NON_TERMINAL_STATUSES } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { pickedBillIdFor } from "app/frontend/components/admin/creator/pipeline-controls/pickedBillId";
import { PIPELINE_LLM_ONLY_PROPS } from "app/frontend/components/admin/creator/pipelineLlmOnlyProps";
import type {
    ILegislationPipelineRun,
    IRecentPipelineRun,
} from "app/frontend/components/admin/creator/pipeline-controls/types";
import PipelineOperatorPasteNotice from "app/frontend/components/admin/creator/pipeline-controls/PipelineOperatorPasteNotice";
import PipelineSummaryBatchNotice from "app/frontend/components/admin/creator/pipeline-controls/PipelineSummaryBatchNotice";
import RunSelector from "app/frontend/components/admin/creator/RunSelector";
import CollapsiblePanel from "app/frontend/components/CollapsiblePanel";
import PerBillGrid from "app/frontend/components/admin/creator/PerBillGrid";
import PipelineProgress from "app/frontend/components/admin/creator/PipelineProgress";
import FetchedBillsPanel from "app/frontend/components/admin/creator/FetchedBillsPanel";
import ResourceCachePanel from "app/frontend/components/admin/creator/ResourceCachePanel";
import TestimonyReport from "app/frontend/components/admin/creator/testimony-report/TestimonyReport";
import SendingServicesPanel from "app/frontend/components/admin/creator/SendingServicesPanel";
import { usePipelineRunSubscription } from "app/frontend/hooks/usePipelineRunSubscription";
import type { FetchedBillsRow, ResourceCacheRow } from "app/frontend/types/bill_creator";
import type {
    ITestimonyCampaignDraft,
    ITestimonyCoverage,
} from "app/frontend/components/admin/creator/llm-summary/types";

interface ITestimonyClaimedAffiliation {
    position: number;
    phrase: string | null;
    role: string | null;
    sender: string | null;
    org_name: string | null;
}
interface ISendingServiceDomain {
    id: number;
    domain: string;
    label: string;
    sender_count: number;
    machine_sent_letter_count: number;
    letter_count: number;
    bill_count: number;
}
type TBill = sway.IBill & {
    bill_llm_provisioning?: {
        generation_status: string | null;
        // @lat: [[bill-creator-pipeline-llm-tab#Why bill_llm_provisioning.llm_generated_at is used as a React key elsewhere]]
        llm_generated_at?: string | null;
        stale?: boolean;
        // @lat: [[lat.md/explanation/llm-summaries#Stand-downs are reported, not swallowed#The pipeline tab warns before it stands down]]
        paste_owns_summary_run?: boolean;
    };
    bill_pipeline_refresh?: { status?: string } | null;
};

// @lat: [[bill-creator-pipeline-llm-tab#Why IPickerBill is a narrow local type]]
interface IPickerBill {
    id: number;
    external_id: string;
}

interface IPageProps {
    bill?: TBill;
    legislation_pipeline_run?: ILegislationPipelineRun | null;
    recent_pipeline_runs?: IRecentPipelineRun[];
    bill_artifact_mirrors?: ResourceCacheRow[];
    // @lat: [[bill-creator-pipeline-llm-tab#Why fetched_bills is never actually missing]]
    fetched_bills?: FetchedBillsRow[];
    // @lat: [[bill-creator-pipeline-llm-tab#Why bills is reused from the picker's props instead of refetched]]
    bills?: IPickerBill[];
    testimony_coverage?: ITestimonyCoverage | null;
    testimony_campaign_drafts?: ITestimonyCampaignDraft[];
    testimony_claimed_affiliations?: ITestimonyClaimedAffiliation[];
    sending_service_domains?: ISendingServiceDomain[];
    sending_service_domains_total?: number;
    [key: string]: unknown;
}

// @lat: [[bill-creator-pipeline-llm-tab#Why this tab is one fixed-order column with a shared connection]]
interface IProps {
    // @lat: [[bill-creator-pipeline-llm-tab#Why onCancelRun is a prop, not local logic]]
    onCancelRun: (runId: number) => void;
}

const BillCreatorPipelineLlm: React.FC<IProps> = ({ onCancelRun }) => {
    const { props } = usePage<IPageProps>();
    const bill = props.bill;
    const run = props.legislation_pipeline_run ?? null;
    const billArtifactMirrors = props.bill_artifact_mirrors ?? [];
    const fetchedBills = props.fetched_bills ?? [];
    // @lat: [[bill-creator-pipeline-llm-tab#Why pickedBillId goes through the same shared helper as the controls]]
    const pickedBillId = pickedBillIdFor(bill?.id);

    // @lat: [[bill-creator-pipeline-llm-tab#Why the subscription is created here, once, for the whole panel]]
    const subscription = usePipelineRunSubscription(run?.remote_run_id ?? null, PIPELINE_LLM_ONLY_PROPS);

    const pipelineRunStatus = run?.status ?? null;
    const billPipelineStatus = bill?.bill_pipeline_refresh?.status ?? null;

    // @lat: [[bill-creator-pipeline-llm-tab#Why isRunInFlight checks a shared non-terminal-status list]]
    const isRunInFlight =
        pipelineRunStatus !== null && (PHASE_52_NON_TERMINAL_STATUSES as readonly string[]).includes(pipelineRunStatus);
    // @lat: [[bill-creator-pipeline-llm-tab#Why isPollingActive doesn't reuse the LLM summary's isPipelineBusy helper]]
    const isPollingActive = isRunInFlight || billPipelineStatus === "queued" || billPipelineStatus === "running";

    // @lat: [[bill-creator-pipeline-llm-tab#Why the backup poll's prop list was merged with the live connection's]]
    const { start: startPolling, stop: stopPolling } = usePoll(
        5000,
        { only: [...PIPELINE_LLM_ONLY_PROPS] },
        { autoStart: false },
    );
    useEffect(() => {
        if (isPollingActive) {
            startPolling();
        } else {
            stopPolling();
        }
    }, [isPollingActive, startPolling, stopPolling]);

    const pipelineRunBills = run?.pipeline_run_bills ?? [];
    // @lat: [[bill-creator-pipeline-llm-tab#Why stagesSucceeded/stagesTotal are memoized]]
    const stagesSucceeded = useMemo(
        () => run?.pipeline_run_stages?.filter((s) => s.status === "succeeded").length ?? 0,
        [run?.pipeline_run_stages],
    );
    const stagesTotal = useMemo(() => run?.pipeline_run_stages?.length ?? 0, [run?.pipeline_run_stages]);

    // @lat: [[bill-creator-pipeline-llm-tab#Why billIdByExternalId is built from the picker's bill list]]
    const billIdByExternalId = useMemo<Record<string, number>>(() => {
        const map: Record<string, number> = {};
        for (const b of props.bills ?? []) {
            map[b.external_id] = b.id;
        }
        return map;
    }, [props.bills]);

    return (
        <div className="max-w-5xl mx-auto flex flex-col gap-6">
            {/* @lat: [[bill-creator-pipeline-llm-tab#Section notes (JSX)]] */}
            <RunSelector runs={props.recent_pipeline_runs ?? []} currentRunId={run?.id ?? null} />

            {run?.kind === "all_bills" && (
                <PerBillGrid
                    rows={pipelineRunBills}
                    currentBillExternalId={bill?.external_id ?? ""}
                    currentStage={run.current_stage}
                    runStatus={run.status}
                    stagesSucceeded={stagesSucceeded}
                    stagesTotal={stagesTotal}
                    billIdByExternalId={billIdByExternalId}
                />
            )}

            <PipelineOperatorPasteNotice pasteOwnsSummaryRun={bill?.bill_llm_provisioning?.paste_owns_summary_run} />

            <PipelineSummaryBatchNotice summaryBatch={run?.summary_batch} />

            {/* @lat: [[bill-creator-pipeline-llm-tab#Section notes (JSX)]] */}
            <BillCreatorPipelineControls subscriptionState={subscription} />

            <PipelineProgress
                run={run}
                pickedBillId={pickedBillId}
                subscription={subscription}
                onCancelRun={onCancelRun}
            />

            <TestimonyReport
                coverage={props.testimony_coverage}
                campaignDrafts={props.testimony_campaign_drafts ?? []}
            />
            {typeof bill?.id === "number" && (
                <SendingServicesPanel
                    billId={bill.id}
                    domains={props.sending_service_domains ?? []}
                    total={props.sending_service_domains_total}
                />
            )}
            <CollapsiblePanel storageKey="sway:pipeline-llm:accordion:resource-cache" title="Resource cache">
                <ResourceCachePanel mirrors={billArtifactMirrors} />
            </CollapsiblePanel>

            <CollapsiblePanel storageKey="sway:pipeline-llm:accordion:fetched-bills" title="Fetched bills (on disk)">
                <FetchedBillsPanel rows={fetchedBills} />
            </CollapsiblePanel>

            <CollapsiblePanel storageKey="sway:pipeline-llm:accordion:activity-log" title="Activity log">
                <ActivityLogPanel
                    currentBillId={bill?.id ?? undefined}
                    currentRunRemoteId={run?.remote_run_id ?? null}
                />
            </CollapsiblePanel>
        </div>
    );
};

export default BillCreatorPipelineLlm;
