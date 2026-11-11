import { router } from "@inertiajs/react";
import { useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import { Textarea } from "app/frontend/components/ui/textarea";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import ClaimedAffiliationEvidence from "app/frontend/components/admin/creator/claimed-affiliation-card/ClaimedAffiliationEvidence";
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
import {
    isPrivateIndividualRefusal,
    notifyServerRefusal,
    serverRefusalMessage,
} from "app/frontend/components/admin/creator/notifyServerRefusal";
import { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import { useInFlightRequests } from "app/frontend/hooks/useInFlightRequests";

// @lat: [[campaign-position-cards#Claimed affiliation card shape and partial-evidence rule]]
export interface IClaimedAffiliationDraft {
    position: number;
    phrase: string | null;
    role: string | null;
    sender: string | null;
    org_name: string | null;
}

interface IProps {
    billId: number;
    draft: IClaimedAffiliationDraft;
    runInFlight: boolean;
    // @lat: [[bill-creator-org-position-card#Why testimonyMissing is required, with no default]]
    testimonyMissing: boolean;
    // @lat: [[bill-creator-org-position-card#Why testimonyLeftOutUnacknowledged is derived once by the caller]]
    testimonyLeftOutUnacknowledged?: boolean;
}

// @lat: [[org-position-draft-identity-exemption#The three caller classes]]
const BillCreatorClaimedAffiliationCard: React.FC<IProps> = ({
    billId,
    draft,
    runInFlight,
    testimonyMissing,
    testimonyLeftOutUnacknowledged = false,
}) => {
    const { position, phrase, role, sender, org_name } = draft;

    const [editing, setEditing] = useState<boolean>(false);
    const [dismissed, setDismissed] = useState<boolean>(false);
    // @lat: [[private-individual-guard-override#A retry started from onError outlives the request that started it]]
    const { inFlight: submitting, begin: beginRequest, end: endRequest } = useInFlightRequests();
    const confirm = useConfirm();

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why the affiliation card seeds from the organization name]]
    const [orgName, setOrgName] = useState<string>(org_name ?? "");
    const [stance, setStance] = useState<TStance>("support");
    const [summary, setSummary] = useState<string>("");

    // @lat: [[campaign-position-cards#Claimed affiliation card shape and partial-evidence rule]]
    if ((!phrase && !role && !sender) || dismissed) return null;

    const slug = `claimed-affiliation-${position}`;

    // @lat: [[private-individual-guard-override]]
    const submitApprove = (overridePrivateIndividual: boolean) => {
        beginRequest();
        router.post(
            `/bills/${billId}/approve_org_position`,
            // @lat: [[org-position-draft-identity-exemption#Why absence is the wrong thing to decide on]]
            {
                org_name: orgName,
                support: stance,
                summary,
                claimed_affiliation_position: position,
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

    const knownStance = STANCE_TO_SUPPORT[stance];
    const stanceBadgeTone = SUPPORT_TO_TONE[knownStance];
    const stanceBadgeLabel = SUPPORT_LABEL[knownStance];

    // @lat: [[org-position-approval-guard-chain#Why summary validation runs first]]
    const summaryMissing = summary.trim().length === 0;
    const summaryMissingNoticeId = `claimed-affiliation-summary-required-${position}`;
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

    return (
        <div
            className="flex flex-col gap-3 rounded-xl border-neo border-border-strong bg-card p-4 shadow-neo"
            data-testid={`claimed-affiliation-card-${slug}`}
        >
            <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="line-clamp-1 min-w-0 flex-1 font-semibold" data-testid="claimed-affiliation-name-line">
                    Maybe: {orgName}
                </span>
                <Badge variant="stamp" tone="warning" data-testid="claimed-affiliation-stamp">
                    CLAIMED, NOT VERIFIED
                </Badge>
            </div>

            <div className="flex flex-col gap-2">
                <div className="flex min-w-0 items-center gap-1.5">
                    <h5 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                        Why this organization
                    </h5>
                    <FeatureInfo note="summary.claimedAffiliationEvidence" />
                </div>
                <ClaimedAffiliationEvidence evidence={{ phrase, role, sender }} />
            </div>

            <p className="text-xs text-muted-foreground">
                The sender said this. Nothing has confirmed it. Approve only if you know it is true.
            </p>

            {editing ? (
                <div className="flex flex-col gap-2">
                    <div className="flex flex-col gap-1">
                        <Label htmlFor={`claimed-affiliation-name-${slug}`}>Organization name</Label>
                        <Input
                            id={`claimed-affiliation-name-${slug}`}
                            data-testid="input-claimed-affiliation-name"
                            value={orgName}
                            onChange={(e) => setOrgName(e.target.value)}
                        />
                    </div>
                    <div className="flex flex-col gap-1">
                        <Label htmlFor={`claimed-affiliation-stance-${slug}`}>Position</Label>
                        <Select value={stance} onValueChange={(v) => setStance(v as TStance)}>
                            <SelectTrigger
                                id={`claimed-affiliation-stance-${slug}`}
                                data-testid="select-claimed-affiliation-stance-trigger"
                            >
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
                        <Label htmlFor={`claimed-affiliation-summary-${slug}`}>Summary</Label>
                        <Textarea
                            id={`claimed-affiliation-summary-${slug}`}
                            data-testid="textarea-claimed-affiliation-summary"
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
                            data-testid="btn-claimed-affiliation-cancel"
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
                    data-testid="btn-approve-claimed-affiliation"
                >
                    Approve
                </Button>
                <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={submitting}
                    onClick={() => setDismissed(true)}
                    data-testid="btn-reject-claimed-affiliation"
                >
                    Reject
                </Button>
                <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    disabled={submitting}
                    onClick={() => setEditing((prev) => !prev)}
                    data-testid="btn-edit-claimed-affiliation"
                >
                    Edit
                </Button>
            </div>
        </div>
    );
};

export default BillCreatorClaimedAffiliationCard;
