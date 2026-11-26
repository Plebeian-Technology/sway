// @lat: [[mobile-bill-creator#Sections#The campaign drafts section#Linking a campaign to an organization]]
import React, { useState } from "react";
import { Text, TextInput, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import { Pressable } from "../../ui/Pressable";

export type OrganizationLinkDecision = "linked" | "none" | "undetermined";

export interface LinkableCampaign {
    id: number;
    organization_link_decision: OrganizationLinkDecision | null;
    organization_id: number | null;
    organization_name: string | null;
}

export interface OrganizationCandidate {
    organization_id: number;
    organization_name: string | null;
    evidence_kind: "signature_block" | "bill_position";
    letter_count: number;
    claimed_name: string | null;
}

interface WriteResponse {
    notice?: string;
}

interface LinkPayload {
    decision: OrganizationLinkDecision;
    organization_id?: string;
    organization_name?: string;
}

interface IProps {
    billId: number;
    campaign: LinkableCampaign;
    candidates: OrganizationCandidate[];
    runInFlight: boolean;
    refresh: () => Promise<void>;
}

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const buttonText = "text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark";
const stampText = `rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const inputClass =
    "rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark";

const countNoun = (count: number, singular: string, plural: string) =>
    `${count.toLocaleString()} ${count === 1 ? singular : plural}`;

// @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
const evidenceLine = (candidate: OrganizationCandidate): string => {
    if (candidate.evidence_kind === "signature_block") {
        const wrote = countNoun(candidate.letter_count, "letter", "letters");
        return candidate.claimed_name
            ? `${wrote} signed off as "${candidate.claimed_name}"`
            : `${wrote} named this organization`;
    }
    return "Already holds a position on this bill";
};

const stampLabel = (campaign: LinkableCampaign): string => {
    switch (campaign.organization_link_decision) {
        case "linked":
            return campaign.organization_name || "LINKED";
        case "none":
            return "NO ORGANIZATION";
        case "undetermined":
            return "NOT DETERMINABLE YET";
        default:
            return "NOT DECIDED";
    }
};

// @lat: [[campaign-organization-link#Why this is a second approval and not part of the first]]
const CampaignOrganizationLink: React.FC<IProps> = ({ billId, campaign, candidates, runInFlight, refresh }) => {
    const testID = `admin-campaign-organization-${campaign.id}`;
    const link = useAdminMutation<WriteResponse>("post", Routes.billCampaignLinkOrganization(billId, campaign.id));

    const serverChoice = campaign.organization_id ? String(campaign.organization_id) : "";
    const decision = campaign.organization_link_decision;
    const [lastServerChoice, setLastServerChoice] = useState(serverChoice);
    const [lastDecision, setLastDecision] = useState(decision);
    const [choice, setChoice] = useState(serverChoice);
    const [newOrganizationName, setNewOrganizationName] = useState("");
    const [notice, setNotice] = useState<string | null>(null);
    if (serverChoice !== lastServerChoice || decision !== lastDecision) {
        setLastServerChoice(serverChoice);
        setLastDecision(decision);
        setChoice(serverChoice);
    }
    const trimmedNewName = newOrganizationName.trim();
    const blocked = link.loading || runInFlight;

    const submit = async (payload: LinkPayload) => {
        setNotice(null);
        const response = await link.run({ ...payload });
        if (response === undefined) return;
        setNotice(response?.notice ?? null);
        setNewOrganizationName("");
        setChoice(payload.decision === "linked" ? (prev) => prev || serverChoice : "");
        await refresh();
    };

    const submitNewName = () => submit({ decision: "linked", organization_name: trimmedNewName });

    const linkedOrganizationMissingFromCandidates =
        campaign.organization_id !== null &&
        !!campaign.organization_name?.trim() &&
        candidates.every((candidate) => candidate.organization_id !== campaign.organization_id);

    const options = [
        ...(linkedOrganizationMissingFromCandidates
            ? [
                  {
                      id: String(campaign.organization_id),
                      label: `${campaign.organization_name} — Linked to this campaign`,
                  },
              ]
            : []),
        ...candidates.map((candidate) => ({
            id: String(candidate.organization_id),
            label: `${candidate.organization_name} — ${evidenceLine(candidate)}`,
        })),
    ];

    const reason = link.fieldErrors?.campaign_organization;
    const refusal = typeof reason === "string" && reason.trim() !== "" ? reason : link.errorMessage;

    return (
        <View testID={testID} className="gap-2 rounded-lg border border-border-light dark:border-border-dark p-3">
            <View className="flex-row flex-wrap items-center justify-between gap-2">
                <Text className={labelText}>Organization behind this campaign</Text>
                <Text testID={`${testID}-stamp`} className={stampText}>
                    {stampLabel(campaign)}
                </Text>
            </View>

            {candidates.length === 0 ? (
                <Text testID={`${testID}-no-candidates`} className={mutedText}>
                    {decision === "linked" && campaign.organization_name
                        ? `Linked to ${campaign.organization_name}. No other organization on this bill matches this campaign's letters.`
                        : "No organization on this bill matches this campaign's letters. Record one of the answers below."}
                </Text>
            ) : (
                <View className="gap-2">
                    <Text className={mutedText}>Choose an organization</Text>
                    {options.map((option) => (
                        <Pressable
                            key={option.id}
                            testID={`${testID}-option-${option.id}`}
                            variant={choice === option.id ? "default" : "outline"}
                            accessibilityRole="radio"
                            accessibilityState={{ selected: choice === option.id }}
                            accessibilityLabel={option.label}
                            onPress={() => {
                                setChoice(option.id);
                                setNewOrganizationName("");
                            }}
                        >
                            <Text className={choice === option.id ? buttonText : labelText}>{option.label}</Text>
                        </Pressable>
                    ))}
                </View>
            )}
            <Text className={mutedText}>
                {candidates.length === 0 ? "Create an organization" : "Or create a new organization"}
            </Text>
            <TextInput
                testID={`${testID}-new-name`}
                value={newOrganizationName}
                placeholder="Enter organization name"
                editable={!blocked}
                accessibilityLabel="Organization name"
                className={inputClass}
                style={{ minHeight: 44 }}
                onChangeText={(value) => {
                    setNewOrganizationName(value);
                    setChoice(value.trim() !== "" ? "" : serverChoice);
                }}
                onSubmitEditing={() => {
                    if (trimmedNewName !== "" && !blocked) void submitNewName();
                }}
            />

            <View className="flex-row flex-wrap gap-2">
                <Pressable
                    testID={`${testID}-link`}
                    variant="default"
                    disabled={blocked || (choice === "" && trimmedNewName === "")}
                    onPress={() =>
                        void (trimmedNewName !== ""
                            ? submitNewName()
                            : submit({ decision: "linked", organization_id: choice }))
                    }
                >
                    <Text className={buttonText}>
                        {trimmedNewName !== ""
                            ? "Create and link organization"
                            : decision === "linked"
                              ? "Change the organization"
                              : "Link this organization"}
                    </Text>
                </Pressable>
                <Pressable
                    testID={`${testID}-none`}
                    variant="outline"
                    disabled={blocked}
                    onPress={() => void submit({ decision: "none" })}
                >
                    <Text className={labelText}>None of these</Text>
                </Pressable>
                <Pressable
                    testID={`${testID}-undetermined`}
                    variant="ghost"
                    disabled={blocked}
                    onPress={() => void submit({ decision: "undetermined" })}
                >
                    <Text className={labelText}>Can&apos;t tell yet</Text>
                </Pressable>
            </View>

            {notice ? (
                <Text testID={`${testID}-notice`} className={mutedText}>
                    {notice}
                </Text>
            ) : null}
            {refusal ? (
                <Text testID={`${testID}-error`} accessibilityRole="alert" className={errorText}>
                    {refusal}
                </Text>
            ) : null}
        </View>
    );
};

export default CampaignOrganizationLink;
