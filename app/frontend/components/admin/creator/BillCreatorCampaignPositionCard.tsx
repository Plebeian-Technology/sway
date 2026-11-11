import { router } from "@inertiajs/react";
import { useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Textarea } from "app/frontend/components/ui/textarea";
import {
    STANCE_OPTIONS,
    SUPPORT_TO_TONE,
    SUPPORT_LABEL,
    STANCE_TO_SUPPORT,
    TStance,
} from "app/frontend/components/admin/creator/org-position-card/constants";
import { NO_TESTIMONY_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/noTestimonyNoticeId";
import { RUN_IN_FLIGHT_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/runInFlightNoticeId";
import { TESTIMONY_COVERAGE_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/testimonyCoverageNoticeId";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import CampaignLetterList from "app/frontend/components/admin/creator/campaign-position-card/CampaignLetterList";
import CampaignOrganizationLink from "app/frontend/components/admin/creator/campaign-position-card/CampaignOrganizationLink";
import {
    IApprovedCampaign,
    ICampaignOrganizationCandidate,
    ITestimonyCampaignDraft,
    ITestimonyCampaignLetter,
} from "app/frontend/components/admin/creator/llm-summary/types";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IProps {
    billId: number;
    draft: ITestimonyCampaignDraft;
    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
    approved?: IApprovedCampaign;
    // @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
    organizationCandidates?: ICampaignOrganizationCandidate[];
    letters?: ITestimonyCampaignLetter[];
    runInFlight: boolean;
    // @lat: [[bill-creator-org-position-card#Why testimonyMissing is required, with no default]]
    testimonyMissing: boolean;
    // @lat: [[bill-creator-org-position-card#Why testimonyLeftOutUnacknowledged is derived once by the caller]]
    testimonyLeftOutUnacknowledged?: boolean;
}

// @lat: [[campaign-position-cards#Display clamp and support-to-stance lookup on the campaign card]]
const NAME_CLAMP_LENGTH = 120;

// @lat: [[campaign-position-cards#Display clamp and support-to-stance lookup on the campaign card]]
const SUPPORT_TO_STANCE: Record<string, TStance | undefined> = {
    FOR: "support",
    AGAINST: "oppose",
    ABSTAIN: "neutral",
};

const unnamedLine = (senderCount: number | null): string =>
    senderCount === null ? "This letter" : `${countNoun(senderCount, "person", "people")} sent this letter`;

// @lat: [[campaign-position-cards]]
const BillCreatorCampaignPositionCard: React.FC<IProps> = ({
    billId,
    draft,
    approved,
    organizationCandidates = [],
    letters,
    runInFlight,
    testimonyMissing,
    testimonyLeftOutUnacknowledged = false,
}) => {
    const [editing, setEditing] = useState<boolean>(false);
    const [submitting, setSubmitting] = useState<boolean>(false);
    const [nameExpanded, setNameExpanded] = useState<boolean>(false);

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#An unnamed campaign is a complete record]]
    const serverName = approved?.name ?? "";
    const serverStance = SUPPORT_TO_STANCE[approved?.support ?? ""] ?? "support";
    const serverSummary = approved?.summary ?? "";
    const [lastServerName, setLastServerName] = useState<string>(serverName);
    const [lastServerStance, setLastServerStance] = useState<TStance>(serverStance);
    const [lastServerSummary, setLastServerSummary] = useState<string>(serverSummary);
    const [name, setName] = useState<string>(serverName);
    const [stance, setStance] = useState<TStance>(serverStance);
    const [summary, setSummary] = useState<string>(serverSummary);

    if (serverName !== lastServerName) {
        setLastServerName(serverName);
        if (!editing) setName(serverName);
    }
    if (serverStance !== lastServerStance) {
        setLastServerStance(serverStance);
        if (!editing) setStance(serverStance);
    }
    if (serverSummary !== lastServerSummary) {
        setLastServerSummary(serverSummary);
        if (!editing) setSummary(serverSummary);
    }

    const slug = `campaign-${draft.content_hash}`;
    const persistedNameLine = (approved?.name ?? "").trim() || unnamedLine(draft.sender_count);
    const nameLine = name.trim() || unnamedLine(draft.sender_count);
    const nameClamped = !nameExpanded && nameLine.length > NAME_CLAMP_LENGTH;

    const evidenceParts = [
        `${countNoun(draft.sender_count, "sender", "senders")}`,
        `${countNoun(draft.letter_count, "letter", "letters")}`,
    ];
    if (draft.domain) evidenceParts.push(`sent through ${draft.domain}`);
    const evidenceSubline = evidenceParts.join(" · ");

    // @lat: [[campaign-approval-guard-chain#Why summary validation runs first]]
    const summaryMissing = summary.trim().length === 0;
    const summaryMissingNoticeId = `campaign-summary-required-${slug}`;
    const approveDisabled = summaryMissing || testimonyMissing || runInFlight || testimonyLeftOutUnacknowledged;
    const approveDisabledReasonId =
        [
            summaryMissing ? summaryMissingNoticeId : null,
            testimonyMissing ? NO_TESTIMONY_NOTICE_ID : null,
            runInFlight ? RUN_IN_FLIGHT_NOTICE_ID : null,
            testimonyLeftOutUnacknowledged ? TESTIMONY_COVERAGE_NOTICE_ID : null,
        ]
            .filter(Boolean)
            .join(" ") || undefined;

    const handleApprove = () => {
        setSubmitting(true);
        router.post(
            `/bills/${billId}/campaigns`,
            {
                name,
                support: stance,
                summary,
                // @lat: [[campaign-position-cards#Approving a campaign out of testimony#The draft's content hash is its whole identity]]
                content_hash: draft.content_hash,
            },
            {
                preserveScroll: true,
                // @lat: [[campaign-approval-outcomes#ApproveCampaignPositionService outcomes]]
                onError: (errors) => notifyServerRefusal(errors, "campaign_position", "Approve failed."),
                onFinish: () => setSubmitting(false),
            },
        );
    };

    // @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
    const handleRejectDecision = (path: string) => {
        setSubmitting(true);
        const fallbackMsg =
            path === "restore_draft"
                ? "Restore failed."
                : path === "mark_individual_draft"
                  ? "Mark individual failed."
                  : "Reject failed.";
        router.post(
            `/bills/${billId}/campaigns/${path}`,
            { content_hash: draft.content_hash },
            {
                preserveScroll: true,
                onError: (errors) => notifyServerRefusal(errors, "campaign_position", fallbackMsg),
                onFinish: () => setSubmitting(false),
            },
        );
    };

    // @lat: [[campaign-draft-rejection#Why a rejected card stays visible]]
    if (draft.rejected) {
        return (
            <div
                className="flex flex-wrap items-center justify-between gap-2 rounded-xl border-neo border-border-strong bg-surface-2 p-3"
                data-testid={`campaign-position-card-${slug}`}
            >
                <span className="flex items-center gap-2">
                    <Badge variant="stamp" tone="neutral" data-testid="campaign-rejected-stamp">
                        REJECTED
                    </Badge>
                    <span className="line-clamp-1 text-sm text-muted-foreground">{persistedNameLine}</span>
                </span>
                <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={submitting}
                    onClick={() => handleRejectDecision("restore_draft")}
                    data-testid="btn-restore-campaign-position"
                >
                    Restore
                </Button>
            </div>
        );
    }

    // @lat: [[campaign-position-cards#Marking false-positive campaign drafts as individual letters]]
    if (draft.marked_individual && !approved) {
        return (
            <div
                className="flex flex-wrap items-center justify-between gap-2 rounded-xl border-neo border-border-strong bg-surface-2 p-3"
                data-testid={`campaign-position-card-${slug}`}
            >
                <span className="flex items-center gap-2">
                    <Badge variant="stamp" tone="warning" data-testid="campaign-individual-stamp">
                        INDIVIDUAL LETTERS
                    </Badge>
                    <span className="line-clamp-1 text-sm text-muted-foreground">
                        {persistedNameLine} · {evidenceSubline}
                    </span>
                </span>
                <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={submitting}
                    onClick={() => handleRejectDecision("restore_draft")}
                    data-testid="btn-restore-campaign-position"
                >
                    Restore
                </Button>
            </div>
        );
    }

    const knownStance = STANCE_TO_SUPPORT[stance];
    const stanceBadgeTone = SUPPORT_TO_TONE[knownStance];
    const stanceBadgeLabel = SUPPORT_LABEL[knownStance];

    return (
        <div
            className="flex flex-col gap-3 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo"
            data-testid={`campaign-position-card-${slug}`}
        >
            <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="min-w-0 flex-1">
                    <span
                        className={nameClamped ? "line-clamp-1 font-semibold" : "font-semibold"}
                        data-testid="campaign-name-line"
                    >
                        {nameLine}
                    </span>
                    {nameLine.length > NAME_CLAMP_LENGTH && (
                        <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            className="ml-1 h-auto min-h-[44px] px-1.5 py-1 text-xs underline sm:min-h-0"
                            onClick={() => setNameExpanded((prev) => !prev)}
                            data-testid="btn-campaign-name-disclosure"
                        >
                            {nameExpanded ? "Show less" : "Show full name"}
                        </Button>
                    )}
                </span>
                <span className="flex items-center gap-2">
                    {approved && (
                        <Badge variant="stamp" tone="success" data-testid="campaign-approved-stamp">
                            APPROVED
                        </Badge>
                    )}
                    <span className="flex items-center gap-1.5">
                        <Badge variant="stamp" tone="neutral" data-testid="campaign-stamp">
                            CAMPAIGN
                        </Badge>
                        <FeatureInfo note="summary.campaignStamp" />
                    </span>
                </span>
            </div>
            <div className="flex min-w-0 items-center gap-1.5">
                <p className="tabular-nums lining-nums text-xs text-muted-foreground">{evidenceSubline}</p>
                <FeatureInfo note="summary.campaignEvidence" />
            </div>
            <CampaignLetterList letters={letters} letterCount={draft.letter_count} />
            <p className="text-xs text-muted-foreground">
                Approving records a campaign position. It never creates an organization.
            </p>

            {/* @lat: [[campaign-organization-link#Why this is a second approval and not part of the first]] */}
            {approved && (
                <CampaignOrganizationLink
                    billId={billId}
                    campaign={approved}
                    candidates={organizationCandidates}
                    runInFlight={runInFlight}
                />
            )}

            {editing ? (
                <div className="flex flex-col gap-2">
                    <div className="flex flex-col gap-1">
                        <Label htmlFor={`campaign-name-${slug}`}>Campaign name</Label>
                        <Input
                            id={`campaign-name-${slug}`}
                            data-testid="input-campaign-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                        />
                    </div>
                    {/* @lat: [[campaign-scope-and-identity#What follows from scoping to a bill]] */}
                    <div className="flex flex-col gap-1">
                        <Label htmlFor={`campaign-stance-${slug}`}>Position</Label>
                        <Select value={stance} onValueChange={(v) => setStance(v as TStance)}>
                            <SelectTrigger id={`campaign-stance-${slug}`} data-testid="select-campaign-stance-trigger">
                                <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                                {STANCE_OPTIONS.map((opt) => (
                                    <SelectItem key={opt.value} value={opt.value}>
                                        {opt.label}
                                    </SelectItem>
                                ))}
                            </SelectContent>
                        </Select>
                    </div>
                    <div className="flex flex-col gap-1">
                        <Label htmlFor={`campaign-summary-${slug}`}>Summary</Label>
                        <Textarea
                            id={`campaign-summary-${slug}`}
                            data-testid="textarea-campaign-summary"
                            rows={3}
                            value={summary}
                            onChange={(e) => setSummary(e.target.value)}
                        />
                    </div>
                    <div className="flex flex-wrap gap-2">
                        <Button
                            type="button"
                            size="sm"
                            variant="ghost"
                            disabled={submitting}
                            onClick={() => setEditing(false)}
                            data-testid="btn-campaign-cancel"
                        >
                            Cancel
                        </Button>
                    </div>
                </div>
            ) : (
                <div className="flex flex-col gap-2">
                    <Badge variant="stamp" tone={stanceBadgeTone} className="w-fit">
                        {stanceBadgeLabel}
                    </Badge>
                    <p className="text-sm text-foreground" id={summaryMissing ? summaryMissingNoticeId : undefined}>
                        {summary || "No summary yet — click Edit to add one."}
                    </p>
                </div>
            )}

            <div className="flex flex-wrap gap-2">
                <Button
                    type="button"
                    size="sm"
                    variant="default"
                    onClick={handleApprove}
                    disabled={submitting || approveDisabled}
                    aria-describedby={approveDisabled ? approveDisabledReasonId : undefined}
                    data-testid="btn-approve-campaign-position"
                >
                    {approved ? "Update this campaign" : "Approve as this campaign"}
                </Button>
                <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={submitting}
                    onClick={() => handleRejectDecision("reject_draft")}
                    data-testid="btn-reject-campaign-position"
                >
                    Reject
                </Button>
                {!approved && (
                    <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        disabled={submitting}
                        onClick={() => handleRejectDecision("mark_individual_draft")}
                        data-testid="btn-mark-individual-campaign-position"
                    >
                        Mark as Individual Letters
                    </Button>
                )}
                <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    disabled={submitting}
                    onClick={() => setEditing((prev) => !prev)}
                    data-testid="btn-edit-campaign-position"
                >
                    Edit
                </Button>
            </div>
        </div>
    );
};

export default BillCreatorCampaignPositionCard;
