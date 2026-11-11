import { memo, useMemo } from "react";
import { usePage } from "@inertiajs/react";
import BillCreatorOrgPositionCard from "app/frontend/components/admin/creator/BillCreatorOrgPositionCard";
import BillCreatorCampaignPositionCard from "app/frontend/components/admin/creator/BillCreatorCampaignPositionCard";
import BillCreatorClaimedAffiliationCard, {
    IClaimedAffiliationDraft,
} from "app/frontend/components/admin/creator/BillCreatorClaimedAffiliationCard";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import LlmSummaryNoTestimonyNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryNoTestimonyNotice";
import LlmSummaryTestimonyCoverageNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryTestimonyCoverageNotice";
import { draftOrgPositionKeys } from "app/frontend/components/admin/creator/llm-summary/draftOrgPositionKeys";
import {
    IApprovedCampaign,
    ICampaignOrganizationCandidate,
    ITestimonyCampaignDraft,
    ITestimonyCampaignLetterBundle,
    ITestimonyCoverage,
    TDraftOrgPosition,
} from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    billId: number;
    orgPositions: TDraftOrgPosition[];
    hasTestimony: boolean;
    // @lat: [[llm-summary-org-positions-list#runInFlight]]
    runInFlight: boolean;
}

// @lat: [[llm-summary-org-positions-list#Test notes (LlmSummaryOrgPositions.test.tsx)]]
interface IPageProps {
    testimony_coverage?: ITestimonyCoverage | null;
    testimony_campaign_drafts?: ITestimonyCampaignDraft[];
    testimony_campaign_letters?: ITestimonyCampaignLetterBundle[];
    testimony_claimed_affiliations?: IClaimedAffiliationDraft[];
    campaigns?: IApprovedCampaign[];
    // @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
    campaign_organization_candidates?: Record<string, ICampaignOrganizationCandidate[]>;
    [key: string]: unknown;
}
const LlmSummaryOrgPositions: React.FC<IProps> = memo(({ billId, orgPositions, hasTestimony, runInFlight }) => {
    // @lat: [[llm-summary-org-positions-list#noTestimony fails closed]]
    const noTestimony = !hasTestimony;
    const hasDrafts = orgPositions.length > 0;
    // @lat: [[llm-summary-org-positions-list#allDraftsRetracted requires every draft, not some]]
    const allDraftsRetracted = hasDrafts && orgPositions.every((p) => !!p.evidence_retracted_at);
    const allNewsSourced =
        hasDrafts &&
        orgPositions.every(
            (p) =>
                (p.bill_news_article_id !== null && p.bill_news_article_id !== undefined) ||
                (p.text_version_id !== null && p.text_version_id !== undefined) ||
                Boolean(p.evidence_excerpt),
        );
    const showNoTestimonyNotice = noTestimony && !allNewsSourced;
    const cardKeys = useMemo(() => draftOrgPositionKeys(orgPositions), [orgPositions]);
    const pageProps = usePage<IPageProps>().props;
    const coverage = pageProps.testimony_coverage;
    const campaignDrafts = pageProps.testimony_campaign_drafts ?? [];
    const claimedAffiliations = pageProps.testimony_claimed_affiliations ?? [];
    const approvedCampaigns = pageProps.campaigns ?? [];
    const organizationCandidates = pageProps.campaign_organization_candidates ?? {};
    // @lat: [[campaign-letter-disclosure#Why the list asks for its own letters]]
    const lettersByHash = useMemo(
        () => new Map((pageProps.testimony_campaign_letters ?? []).map((b) => [b.content_hash, b.letters])),
        [pageProps.testimony_campaign_letters],
    );
    // @lat: [[llm-summary-org-positions-list#Testimony coverage notice and unified draft card list]]
    const testimonyLeftOutUnacknowledged = !!coverage && coverage.coverage_gap && !coverage.acknowledged;

    return (
        <div className="flex flex-col gap-3">
            <div className="flex min-w-0 items-center gap-1.5">
                <h4 className="text-base font-medium">Draft positions</h4>
                <FeatureInfo note="summary.draftOrgPositions" />
            </div>
            <div className="border-b-neo border-border" />
            {showNoTestimonyNotice && (
                <LlmSummaryNoTestimonyNotice hasDrafts={hasDrafts} allDraftsRetracted={allDraftsRetracted} />
            )}
            {/* @lat: [[llm-summary-org-positions-list#Testimony coverage notice and unified draft card list]] */}
            {coverage && (
                <LlmSummaryTestimonyCoverageNotice billId={billId} coverage={coverage} runInFlight={runInFlight} />
            )}
            {!hasDrafts && !noTestimony && (
                <p className="text-sm italic text-muted-foreground">No draft positions generated.</p>
            )}
            {hasDrafts && (
                <div className="flex flex-col gap-3">
                    {/* @lat: [[bill-creator-llm-summary-actions#Why LlmSummaryOrgPositions's card key must not shift on approve/reject]] */}
                    {orgPositions.map((position, i) => (
                        <BillCreatorOrgPositionCard
                            key={cardKeys[i]}
                            billId={billId}
                            index={position.rawIndex}
                            orgPosition={position}
                            testimonyMissing={noTestimony}
                            runInFlight={runInFlight}
                            testimonyLeftOutUnacknowledged={testimonyLeftOutUnacknowledged}
                        />
                    ))}
                </div>
            )}
            {/* @lat: [[llm-summary-org-positions-list#Testimony coverage notice and unified draft card list]] */}
            {campaignDrafts.length > 0 && (
                <div className="flex flex-col gap-3">
                    {campaignDrafts.map((draft, i) => {
                        const approved = approvedCampaigns.find(
                            (c) => c.source_campaign_draft_hash === draft.content_hash,
                        );
                        return (
                            <BillCreatorCampaignPositionCard
                                key={draft.content_hash || i}
                                billId={billId}
                                draft={draft}
                                approved={approved}
                                organizationCandidates={
                                    approved ? organizationCandidates[String(approved.id)] : undefined
                                }
                                letters={lettersByHash.get(draft.content_hash)}
                                runInFlight={runInFlight}
                                testimonyMissing={noTestimony}
                                testimonyLeftOutUnacknowledged={testimonyLeftOutUnacknowledged}
                            />
                        );
                    })}
                </div>
            )}
            {/* @lat: [[llm-summary-org-positions-list#Testimony coverage notice and unified draft card list]] */}
            {claimedAffiliations.length > 0 && (
                <div className="flex flex-col gap-3">
                    {claimedAffiliations.map((draft) => (
                        <BillCreatorClaimedAffiliationCard
                            key={draft.position}
                            billId={billId}
                            draft={draft}
                            runInFlight={runInFlight}
                            testimonyMissing={noTestimony}
                            testimonyLeftOutUnacknowledged={testimonyLeftOutUnacknowledged}
                        />
                    ))}
                </div>
            )}
        </div>
    );
});

LlmSummaryOrgPositions.displayName = "LlmSummaryOrgPositions";

export default LlmSummaryOrgPositions;
