import { router } from "@inertiajs/react";
import { useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "app/frontend/components/ui/select";
import {
    IApprovedCampaign,
    ICampaignOrganizationCandidate,
} from "app/frontend/components/admin/creator/llm-summary/types";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { countNoun } from "app/frontend/sway_utils/countNoun";

interface IProps {
    billId: number;
    campaign: IApprovedCampaign;
    candidates: ICampaignOrganizationCandidate[];
    runInFlight: boolean;
}
// @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]

const evidenceLine = (candidate: ICampaignOrganizationCandidate): string => {
    if (candidate.evidence_kind === "signature_block") {
        const wrote = countNoun(candidate.letter_count, "letter", "letters");
        return candidate.claimed_name
            ? `${wrote} signed off as "${candidate.claimed_name}"`
            : `${wrote} named this organization`;
    }
    return "Already holds a position on this bill";
};

// @lat: [[campaign-organization-link#Why this is a second approval and not part of the first]]
const CampaignOrganizationLink: React.FC<IProps> = ({ billId, campaign, candidates, runInFlight }) => {
    const [submitting, setSubmitting] = useState<boolean>(false);
    const serverChoice = campaign.organization_id ? String(campaign.organization_id) : "";
    const decision = campaign.organization_link_decision;
    const [lastServerChoice, setLastServerChoice] = useState<string>(serverChoice);
    const [lastDecision, setLastDecision] = useState<typeof decision>(decision);
    const [choice, setChoice] = useState<string>(serverChoice);
    const [newOrganizationName, setNewOrganizationName] = useState<string>("");
    if (serverChoice !== lastServerChoice || decision !== lastDecision) {
        setLastServerChoice(serverChoice);
        setLastDecision(decision);
        setChoice(serverChoice);
    }
    const trimmedNewName = newOrganizationName.trim();

    const slug = `campaign-organization-${campaign.id}`;

    const submit = (payload: { decision: string; organization_id?: string; organization_name?: string }) => {
        setSubmitting(true);
        router.post(`/bills/${billId}/campaigns/${campaign.id}/link_organization`, payload, {
            preserveScroll: true,
            onSuccess: () => {
                setNewOrganizationName("");
                if (payload.decision !== "linked") {
                    setChoice("");
                } else {
                    setChoice((prev) => prev || serverChoice);
                }
            },
            // @lat: [[refusal-key-catalog#Why a fixed union instead of string]]
            onError: (errors) =>
                notifyServerRefusal(errors, "campaign_organization", "Saving the organization failed."),
            onFinish: () => setSubmitting(false),
        });
    };

    const linkedOrgMissingFromCandidates =
        campaign.organization_id !== null &&
        campaign.organization_name !== null &&
        campaign.organization_name.trim() !== "" &&
        candidates.every((c) => c.organization_id !== campaign.organization_id);

    return (
        <div className="flex flex-col gap-2 rounded-lg border-neo border-border-strong bg-surface-2 p-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-1.5">
                    <span className="text-xs font-semibold uppercase tracking-widest">
                        Organization behind this campaign
                    </span>
                    <FeatureInfo note="summary.campaignOrgLink" />
                </span>
                {decision === "linked" && (
                    <Badge variant="stamp" tone="success" data-testid="campaign-organization-linked-stamp">
                        {campaign.organization_name || "LINKED"}
                    </Badge>
                )}
                {decision === "none" && (
                    <Badge variant="stamp" tone="neutral" data-testid="campaign-organization-none-stamp">
                        NO ORGANIZATION
                    </Badge>
                )}
                {decision === "undetermined" && (
                    <Badge variant="stamp" tone="neutral" data-testid="campaign-organization-undetermined-stamp">
                        NOT DETERMINABLE YET
                    </Badge>
                )}
                {!decision && (
                    <Badge variant="stamp" tone="neutral" data-testid="campaign-organization-undecided-stamp">
                        NOT DECIDED
                    </Badge>
                )}
            </div>

            {candidates.length === 0 ? (
                <p className="text-xs text-muted-foreground" data-testid="campaign-organization-no-candidates">
                    {decision === "linked" && campaign.organization_name
                        ? `Linked to ${campaign.organization_name}. No other organization on this bill matches this campaign's letters.`
                        : "No organization on this bill matches this campaign's letters. Record one of the answers below."}
                </p>
            ) : (
                <div className="flex flex-col gap-1">
                    <Label htmlFor={slug}>Choose an organization</Label>
                    <Select
                        value={choice}
                        onValueChange={(value) => {
                            setChoice(value);
                            setNewOrganizationName("");
                        }}
                    >
                        <SelectTrigger id={slug} data-testid="select-campaign-organization-trigger">
                            <SelectValue placeholder="Select an organization" />
                        </SelectTrigger>
                        <SelectContent>
                            {linkedOrgMissingFromCandidates && (
                                <SelectItem key={campaign.organization_id} value={String(campaign.organization_id)}>
                                    {campaign.organization_name} — Linked to this campaign
                                </SelectItem>
                            )}
                            {candidates.map((candidate) => (
                                <SelectItem key={candidate.organization_id} value={String(candidate.organization_id)}>
                                    {candidate.organization_name} — {evidenceLine(candidate)}
                                </SelectItem>
                            ))}
                        </SelectContent>
                    </Select>
                </div>
            )}

            <div className="flex flex-col gap-1">
                <Label htmlFor={`${slug}-new-name`}>
                    {candidates.length === 0 ? "Create an organization" : "Or create a new organization"}
                </Label>
                <Input
                    id={`${slug}-new-name`}
                    type="text"
                    value={newOrganizationName}
                    placeholder="Enter organization name"
                    disabled={submitting || runInFlight}
                    onChange={(e) => {
                        const value = e.target.value;
                        setNewOrganizationName(value);
                        if (value.trim() !== "") {
                            setChoice("");
                        } else {
                            setChoice(serverChoice);
                        }
                    }}
                    onKeyDown={(e) => {
                        if (e.key === "Enter" && trimmedNewName !== "" && !submitting && !runInFlight) {
                            e.preventDefault();
                            submit({ decision: "linked", organization_name: trimmedNewName });
                        }
                    }}
                    data-testid="input-create-campaign-organization"
                />
            </div>

            <div className="flex flex-wrap gap-2">
                <Button
                    type="button"
                    size="sm"
                    variant="default"
                    disabled={submitting || runInFlight || (choice === "" && trimmedNewName === "")}
                    onClick={() =>
                        submit(
                            trimmedNewName !== ""
                                ? { decision: "linked", organization_name: trimmedNewName }
                                : { decision: "linked", organization_id: choice },
                        )
                    }
                    data-testid="btn-link-campaign-organization"
                >
                    {trimmedNewName !== ""
                        ? "Create and link organization"
                        : decision === "linked"
                          ? "Change the organization"
                          : "Link this organization"}
                </Button>
                <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={submitting || runInFlight}
                    onClick={() => submit({ decision: "none" })}
                    data-testid="btn-campaign-organization-none"
                >
                    None of these
                </Button>
                <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    disabled={submitting || runInFlight}
                    onClick={() => submit({ decision: "undetermined" })}
                    data-testid="btn-campaign-organization-undetermined"
                >
                    Can&apos;t tell yet
                </Button>
            </div>
        </div>
    );
};

export default CampaignOrganizationLink;
