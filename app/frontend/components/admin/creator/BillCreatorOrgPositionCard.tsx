import { router } from "@inertiajs/react";
import { useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import BillCreatorOrgPositionCardActions from "app/frontend/components/admin/creator/org-position-card/BillCreatorOrgPositionCardActions";
import BillCreatorOrgPositionCardEditor from "app/frontend/components/admin/creator/org-position-card/BillCreatorOrgPositionCardEditor";
import {
    STANCE_TO_SUPPORT,
    SUPPORT_LABEL,
    SUPPORT_TO_TONE,
    TStance,
} from "app/frontend/components/admin/creator/org-position-card/constants";
import type { TSupport } from "app/frontend/sway_constants";
import { IOrgPosition } from "app/frontend/components/admin/creator/llm-summary/types";
import { NO_TESTIMONY_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/noTestimonyNoticeId";
import { RUN_IN_FLIGHT_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/runInFlightNoticeId";
import { TESTIMONY_COVERAGE_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/testimonyCoverageNoticeId";
import {
    isPrivateIndividualRefusal,
    notifyServerRefusal,
    serverRefusalMessage,
} from "app/frontend/components/admin/creator/notifyServerRefusal";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { useInFlightRequests } from "app/frontend/hooks/useInFlightRequests";
import { isSafeUrl } from "app/frontend/sway_utils/safeHref";

interface IProps {
    billId: number;
    // @lat: [[bill-creator-org-position-card#Why handleApprove sends both index and the original draft identity]]
    index: number;
    orgPosition: IOrgPosition;
    // @lat: [[bill-creator-org-position-card#Why testimonyMissing is required, with no default]]
    testimonyMissing: boolean;
    // @lat: [[bill-creator-org-position-card#Why testimonyMissing is required, with no default]]
    runInFlight: boolean;
    // @lat: [[bill-creator-org-position-card#Why testimonyLeftOutUnacknowledged is derived once by the caller]]
    testimonyLeftOutUnacknowledged?: boolean;
}

// @lat: [[bill-creator-org-position-card#Why the component works the way it does (no reload after Approve/Reject)]]
const BillCreatorOrgPositionCard: React.FC<IProps> = ({
    billId,
    index,
    orgPosition,
    testimonyMissing,
    runInFlight,
    testimonyLeftOutUnacknowledged = false,
}) => {
    const {
        org_name,
        stance: initialStance,
        summary: initialSummary,
        draft_token,
        evidence_retracted_at,
        bill_news_article_id,
        text_version_id,
        evidence_excerpt,
        speaker_name,
        speaker_role,
        source_url,
        outlet_name,
        article_title,
        excerpt_page,
        excerpt_paragraph,
        excerpt_offset,
    } = orgPosition;

    const isNewsSourced =
        (bill_news_article_id !== null && bill_news_article_id !== undefined) ||
        (text_version_id !== null && text_version_id !== undefined) ||
        Boolean(evidence_excerpt);
    const [editing, setEditing] = useState<boolean>(false);
    // @lat: [[private-individual-guard-override#A retry started from onError outlives the request that started it]]
    const { inFlight: submitting, begin: beginRequest, end: endRequest } = useInFlightRequests();
    const confirm = useConfirm();

    const [orgName, setOrgName] = useState<string>(org_name);
    const [stance, setStance] = useState<TStance>(initialStance);
    const [summary, setSummary] = useState<string>(initialSummary);

    const handleSaveEdit = (next: { orgName: string; stance: TStance; summary: string }) => {
        setOrgName(next.orgName);
        setStance(next.stance);
        setSummary(next.summary);
        setEditing(false);
    };

    // @lat: [[private-individual-guard-override]]
    const submitApprove = (overridePrivateIndividual: boolean) => {
        beginRequest();
        // @lat: [[bill-creator-org-position-card#Why handleApprove sends both index and the original draft identity]]
        // @lat: [[draft-org-position-identity#draft_token: an identity worked out from content]]
        router.post(
            `/bills/${billId}/approve_org_position`,
            {
                org_name: orgName,
                support: stance,
                summary,
                index,
                draft_org_name: org_name,
                draft_token,
                ...(overridePrivateIndividual ? { override_private_individual: true } : {}),
            },
            {
                preserveScroll: true,
                onError: (errors) => handleApproveError(errors, overridePrivateIndividual),
                onFinish: () => endRequest(),
            },
        );
    };

    // @lat: [[private-individual-guard-override#A refusal that survives the override is shown, not re-asked]]
    const handleApproveError = async (errors: unknown, overrideAlreadyUsed: boolean) => {
        if (!overrideAlreadyUsed && isPrivateIndividualRefusal(errors)) {
            const message = serverRefusalMessage(errors, "org_position") ?? "Approve failed.";
            const confirmed = await confirm({
                title: "Approve anyway?",
                description: `${message} Approving publishes this name as a followable organization.`,
                confirmLabel: "Approve anyway",
                cancelLabel: "Cancel",
                tone: "destructive",
            });
            if (confirmed) {
                submitApprove(true);
                return;
            }
        }
        notifyServerRefusal(errors, "org_position", "Approve failed.");
    };

    const handleApprove = () => submitApprove(false);

    const handleReject = () => {
        beginRequest();
        // @lat: [[bill-creator-org-position-card#Why handleReject carries the same original identity as Approve]]
        router.patch(
            `/bill_draft_org_positions/${billId}-${index}`,
            { rejected: true, draft_org_name: org_name, draft_token },
            {
                preserveScroll: true,
                onError: (errors) => notifyServerRefusal(errors, "org_position", "Reject failed."),
                onFinish: () => endRequest(),
            },
        );
    };

    // @lat: [[bill-creator-org-position-card#Why the card's DOM id (slug) is org_name + index, not org_name alone]]
    const slug = `${org_name.toLowerCase().replace(/\s+/g, "-")}-${index}`;

    // @lat: [[bill-creator-org-position-card#Why the stance badge falls back to the stored word instead of hiding]]
    const knownStance: TSupport | undefined = STANCE_TO_SUPPORT[stance];
    const stanceBadgeKey = knownStance ?? "ABSTAIN";
    const stanceBadgeLabel = knownStance ? SUPPORT_LABEL[knownStance] : stance || "No position";

    // @lat: [[bill-creator-org-position-card#Why Reject and Edit stay usable when evidence is retracted]]
    // @lat: [[evidence-retraction-writers#SupplementalTestimonyWrite.evidence_retraction_attrs]]
    const evidenceRetracted = !!evidence_retracted_at;

    // @lat: [[bill-creator-org-position-card#Why approveDisabledReasonId is built as a filtered, joined list]]
    // @lat: [[org-position-approval-guard-chain#The pre-check / re-check split#run_in_flight?]]
    const approveDisabled =
        evidenceRetracted ||
        (!isNewsSourced && testimonyMissing) ||
        runInFlight ||
        (!isNewsSourced && testimonyLeftOutUnacknowledged);

    // @lat: [[bill-creator-org-position-card#Why approveDisabledReasonId is built as a filtered, joined list]]
    const retractedNoticeId = `org-position-evidence-retracted-${slug}`;
    const approveDisabledReasonId =
        [
            evidenceRetracted ? retractedNoticeId : null,
            !isNewsSourced && testimonyMissing ? NO_TESTIMONY_NOTICE_ID : null,
            runInFlight ? RUN_IN_FLIGHT_NOTICE_ID : null,
            !isNewsSourced && testimonyLeftOutUnacknowledged ? TESTIMONY_COVERAGE_NOTICE_ID : null,
        ]
            .filter(Boolean)
            .join(" ") || undefined;

    return (
        <div
            className="flex flex-col gap-3 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo"
            data-testid={`org-position-card-${slug}`}
        >
            <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-semibold">{orgName}</span>
                <span className="flex items-center gap-1.5">
                    <Badge variant="stamp" tone={SUPPORT_TO_TONE[stanceBadgeKey]}>
                        {stanceBadgeLabel}
                    </Badge>
                    <FeatureInfo note="summary.stanceBadge" />
                </span>
            </div>
            <p className="text-sm text-foreground">{summary}</p>
            {evidence_excerpt && (
                <blockquote
                    data-testid={`draft-org-position-news-excerpt-${index}`}
                    className="my-1 border-l-2 border-border-strong pl-3 text-sm italic text-foreground"
                >
                    <p className="not-italic">“{evidence_excerpt}”</p>
                    <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs not-italic text-muted-foreground">
                        {(speaker_name || speaker_role) && (
                            <span className="font-medium">
                                — {[speaker_name, speaker_role].filter(Boolean).join(", ")}
                            </span>
                        )}
                        {source_url &&
                            (isSafeUrl(source_url) ? (
                                <a
                                    href={source_url}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="underline hover:text-foreground"
                                >
                                    {outlet_name || article_title || source_url}
                                </a>
                            ) : (
                                <span>{outlet_name || article_title || source_url}</span>
                            ))}
                        <span className="text-muted-foreground">
                            {[
                                excerpt_page !== null && excerpt_page !== undefined ? `p. ${excerpt_page}` : null,
                                excerpt_paragraph !== null && excerpt_paragraph !== undefined
                                    ? `para. ${excerpt_paragraph}`
                                    : null,
                                excerpt_offset !== null && excerpt_offset !== undefined
                                    ? `char ${excerpt_offset}`
                                    : null,
                            ]
                                .filter(Boolean)
                                .join(", ")}
                        </span>
                    </div>
                </blockquote>
            )}
            {evidenceRetracted && (
                <p
                    id={retractedNoticeId}
                    className="rounded-lg border-neo border-border-strong bg-muted p-3 text-sm text-foreground"
                    data-testid="org-position-evidence-retracted"
                >
                    {/* @lat: [[bill-creator-org-position-card#Why the evidence-retracted notice names no specific cause]] */}
                    The testimony this draft was drawn from is no longer on this bill, so it cannot be approved.
                    Regenerate the positions once testimony is available, or reject this draft.
                </p>
            )}
            {editing ? (
                <BillCreatorOrgPositionCardEditor
                    slug={slug}
                    initialOrgName={orgName}
                    initialStance={stance}
                    initialSummary={summary}
                    onSave={handleSaveEdit}
                    onCancel={() => setEditing(false)}
                />
            ) : (
                <BillCreatorOrgPositionCardActions
                    submitting={submitting}
                    approveDisabled={approveDisabled}
                    approveDisabledReasonId={approveDisabledReasonId}
                    onApprove={handleApprove}
                    onReject={handleReject}
                    onEdit={() => setEditing(true)}
                />
            )}
        </div>
    );
};

export default BillCreatorOrgPositionCard;
