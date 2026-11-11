import { usePage, usePoll } from "@inertiajs/react";
import { isPipelineBusy, TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import type {
    IApprovedCampaign,
    ITestimonyCampaignDraft,
    ITestimonyCoverage,
} from "app/frontend/components/admin/creator/llm-summary/types";
import type { IClaimedAffiliationDraft } from "app/frontend/components/admin/creator/BillCreatorClaimedAffiliationCard";
import { usePipelineRunSubscription } from "app/frontend/hooks/usePipelineRunSubscription";
import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import BillCreatorOrganizationDraftCache from "app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCache";
import BillCreatorTestimonyPositions from "app/frontend/components/admin/creator/BillCreatorTestimonyPositions";
import { organizationsFormKey } from "app/frontend/components/admin/creator/organizations/organizationsFormKey";

// @lat: [[bill-creator-positions-tab#Splitting the tab split the poll list]]
const POSITIONS_ONLY_PROPS = [
    "bill",
    "organizations",
    "active_legislation_pipeline_run",
    "testimony_coverage",
    "testimony_campaign_drafts",
    "testimony_claimed_affiliations",
    "campaigns",
    "campaign_organization_candidates",
    "public_testimony_counts",
] as const;

interface ILegislationPipelineRun {
    remote_run_id?: string | null;
    status?: string | null;
}

interface IPageProps {
    bill?: {
        id?: number | null;
        organizations?: Array<{ id: number }>;
        bill_llm_provisioning?: { generation_status?: string | null } | null;
        bill_pipeline_refresh?: { status?: TBillPipelineStatus } | null;
    };
    active_legislation_pipeline_run?: ILegislationPipelineRun | null;
    // @lat: [[partial-reload-poll-lists#What a tab's list has to carry besides its own props]]
    testimony_coverage?: ITestimonyCoverage | null;
    testimony_campaign_drafts?: ITestimonyCampaignDraft[];
    testimony_claimed_affiliations?: IClaimedAffiliationDraft[];
    campaigns?: IApprovedCampaign[];
    [key: string]: unknown;
}

const ARGUMENTS_TITLE_ID = "supporting-opposing-arguments-title";

const POLL_INTERVAL_MS = 5000;

// @lat: [[bill-creator-positions-tab#What the positions tab polls for]]
const PositionsPoller: React.FC<Record<string, never>> = () => {
    usePoll(POLL_INTERVAL_MS, { only: [...POSITIONS_ONLY_PROPS] });
    return null;
};

interface IProps {
    setCreatorDirty?: React.Dispatch<React.SetStateAction<boolean>>;
}

// @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
const BillCreatorPositions: React.FC<IProps> = ({ setCreatorDirty }) => {
    const { props } = usePage<IPageProps>();
    const bill = props.bill;
    const run = props.active_legislation_pipeline_run ?? null;
    const isNoBillId = !(bill?.id && bill.id > 0);

    usePipelineRunSubscription(run?.remote_run_id ?? null, POSITIONS_ONLY_PROPS);

    const isGenerating =
        bill?.bill_llm_provisioning?.generation_status === "pending" ||
        bill?.bill_llm_provisioning?.generation_status === "generating";

    const isBillPipelineRunning = isPipelineBusy(bill?.bill_pipeline_refresh?.status ?? null);

    if (isNoBillId) {
        return (
            <div className="flex flex-col gap-8" data-testid="positions-tab">
                <p className="text-sm text-muted-foreground" data-testid="positions-no-bill-selected">
                    Select a bill above to work through its testimony and organization positions.
                </p>
            </div>
        );
    }

    return (
        <div className="flex flex-col gap-8" data-testid="positions-tab">
            {(isGenerating || isBillPipelineRunning) && <PositionsPoller />}

            <BillCreatorTestimonyPositions />

            <section
                aria-labelledby={ARGUMENTS_TITLE_ID}
                className="flex flex-col gap-4 border-t-neo border-border pt-6"
            >
                <h3 id={ARGUMENTS_TITLE_ID} className="text-lg font-semibold">
                    Supporting / opposing arguments
                </h3>
                <BillCreatorOrganizationDraftCache key={`org-drafts-${bill?.id ?? 0}`}>
                    {/* @lat: [[bill-creator-organization-form#The cache outlives the organization-set form]] */}
                    <BillCreatorOrganizations key={organizationsFormKey(bill)} setCreatorDirty={setCreatorDirty} />
                </BillCreatorOrganizationDraftCache>
            </section>
        </div>
    );
};

export default BillCreatorPositions;
export { POSITIONS_ONLY_PROPS };
