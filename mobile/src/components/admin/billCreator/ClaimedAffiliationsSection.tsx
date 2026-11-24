// @lat: [[mobile-bill-creator#Sections#The claimed affiliations section]]
import React, { useState } from "react";
import { Text, TextInput, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { Pressable } from "../../ui/Pressable";

type Stance = "support" | "oppose" | "neutral";

interface ClaimedAffiliation {
    position: number;
    phrase: string | null;
    role: string | null;
    sender: string | null;
    org_name: string | null;
}

interface ApprovalGuards {
    testimonyMissing: boolean;
    runInFlight: boolean;
    testimonyLeftOutUnacknowledged: boolean;
}

const STANCE_LABELS: Record<Stance, string> = { support: "Support", oppose: "Oppose", neutral: "Neutral" };
const STANCES: Stance[] = ["support", "oppose", "neutral"];

const PHRASE_DISCLOSURE_THRESHOLD_CHARS = 160;
const PHRASE_CLIPPED_LINES = 2;

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const evidenceHeading =
    "text-xs font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark";
const buttonText = "text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark";
const stampText = `rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";
const inputClass =
    "rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark";

interface EvidenceRowProps {
    heading: string;
    children: React.ReactNode;
}

const EvidenceRow: React.FC<EvidenceRowProps> = ({ heading, children }) => (
    <View className="gap-1">
        <Text className={evidenceHeading}>{heading}</Text>
        {children}
    </View>
);

const Evidence: React.FC<{ claim: ClaimedAffiliation }> = ({ claim: { phrase, role, sender } }) => {
    const [phraseExpanded, setPhraseExpanded] = useState(false);
    const phraseNeedsDisclosure = !!phrase && phrase.length > PHRASE_DISCLOSURE_THRESHOLD_CHARS;

    return (
        <View className="gap-3">
            {phrase ? (
                <EvidenceRow heading="Phrase">
                    <Text
                        className={bodyText}
                        numberOfLines={phraseNeedsDisclosure && !phraseExpanded ? PHRASE_CLIPPED_LINES : undefined}
                    >
                        {phrase}
                    </Text>
                    {phraseNeedsDisclosure ? (
                        <Pressable variant="ghost" onPress={() => setPhraseExpanded((expanded) => !expanded)}>
                            <Text className={labelText}>{phraseExpanded ? "Show less" : "Show the whole phrase"}</Text>
                        </Pressable>
                    ) : null}
                </EvidenceRow>
            ) : null}
            {role ? (
                <EvidenceRow heading="Role claimed">
                    <Text className={bodyText}>{role}</Text>
                </EvidenceRow>
            ) : null}
            {sender ? (
                <EvidenceRow heading="Sender">
                    <Text className={bodyText}>{sender}</Text>
                </EvidenceRow>
            ) : null}
        </View>
    );
};

interface ClaimedAffiliationCardProps {
    billId: number;
    claim: ClaimedAffiliation;
    guards: ApprovalGuards;
    refresh: () => Promise<void>;
}

const ClaimedAffiliationCard: React.FC<ClaimedAffiliationCardProps> = ({ billId, claim, guards, refresh }) => {
    const testID = `admin-claimed-affiliation-${claim.position}`;
    const approve = useAdminMutation<unknown>("post", Routes.billApproveOrgPosition(billId));

    const [orgName, setOrgName] = useState(claim.org_name ?? "");
    const [stance, setStance] = useState<Stance>("support");
    const [summary, setSummary] = useState("");
    const [editing, setEditing] = useState(false);
    const [dismissed, setDismissed] = useState(false);
    const [overrideSent, setOverrideSent] = useState(false);
    const [overrideDismissed, setOverrideDismissed] = useState(false);

    if ((!claim.phrase && !claim.role && !claim.sender) || dismissed) return null;

    const submitApprove = async (overridePrivateIndividual: boolean) => {
        setOverrideSent(overridePrivateIndividual);
        setOverrideDismissed(false);
        const response = await approve.run({
            org_name: orgName,
            support: stance,
            summary,
            claimed_affiliation_position: claim.position,
            ...(overridePrivateIndividual ? { override_private_individual: true } : {}),
        });
        if (response !== undefined) await refresh();
    };

    const summaryMissing = summary.trim().length === 0;
    const approveDisabled =
        summaryMissing ||
        guards.testimonyMissing ||
        guards.runInFlight ||
        guards.testimonyLeftOutUnacknowledged ||
        approve.loading;

    const reason = approve.fieldErrors?.org_position;
    const refusal = typeof reason === "string" && reason.trim() !== "" ? reason : approve.errorMessage;
    const offerOverride =
        approve.fieldErrors?.private_individual_refusal === true && !overrideSent && !overrideDismissed;

    return (
        <View testID={testID} className={panelClass}>
            <View className="flex-row flex-wrap items-center justify-between gap-2">
                <Text testID={`${testID}-name`} className={labelText}>
                    {`Maybe: ${orgName}`}
                </Text>
                <Text className={stampText}>CLAIMED, NOT VERIFIED</Text>
            </View>
            <Text className={evidenceHeading}>Why this organization</Text>
            <Evidence claim={claim} />
            <Text className={mutedText}>
                The sender said this. Nothing has confirmed it. Approve only if you know it is true.
            </Text>
            {editing ? (
                <View className="gap-2">
                    <Text className={mutedText}>Organization name</Text>
                    <TextInput
                        testID={`${testID}-edit-name`}
                        value={orgName}
                        onChangeText={setOrgName}
                        accessibilityLabel="Organization name"
                        className={inputClass}
                        style={{ minHeight: 44 }}
                    />
                    <Text className={mutedText}>Position</Text>
                    <View className="flex-row flex-wrap gap-2">
                        {STANCES.map((option) => (
                            <Pressable
                                key={option}
                                testID={`${testID}-edit-stance-${option}`}
                                variant={stance === option ? "default" : "outline"}
                                accessibilityRole="radio"
                                accessibilityState={{ selected: stance === option }}
                                accessibilityLabel={STANCE_LABELS[option]}
                                onPress={() => setStance(option)}
                            >
                                <Text className={labelText}>{STANCE_LABELS[option]}</Text>
                            </Pressable>
                        ))}
                    </View>
                    <Text className={mutedText}>Summary</Text>
                    <TextInput
                        testID={`${testID}-edit-summary`}
                        value={summary}
                        onChangeText={setSummary}
                        multiline
                        numberOfLines={3}
                        accessibilityLabel="Summary"
                        className={inputClass}
                        style={{ minHeight: 88, textAlignVertical: "top" }}
                    />
                    <Pressable
                        testID={`${testID}-edit-cancel`}
                        variant="ghost"
                        disabled={approve.loading}
                        onPress={() => setEditing(false)}
                    >
                        <Text className={labelText}>Cancel</Text>
                    </Pressable>
                </View>
            ) : (
                <View className="gap-2">
                    <Text testID={`${testID}-stance`} className={stampText}>
                        {STANCE_LABELS[stance]}
                    </Text>
                    <Text testID={`${testID}-summary`} className={bodyText}>
                        {summary || "No summary yet — press Edit to add one."}
                    </Text>
                </View>
            )}
            <View className="flex-row flex-wrap gap-2">
                <Pressable
                    testID={`${testID}-approve`}
                    variant="default"
                    disabled={approveDisabled}
                    accessibilityLabel={`Approve ${orgName}`}
                    onPress={() => void submitApprove(false)}
                >
                    <Text className={buttonText}>Approve</Text>
                </Pressable>
                <Pressable
                    testID={`${testID}-reject`}
                    variant="outline"
                    disabled={approve.loading}
                    accessibilityLabel={`Reject ${orgName}`}
                    onPress={() => setDismissed(true)}
                >
                    <Text className={labelText}>Reject</Text>
                </Pressable>
                <Pressable
                    testID={`${testID}-edit`}
                    variant="ghost"
                    disabled={approve.loading}
                    accessibilityLabel={`Edit ${orgName}`}
                    onPress={() => setEditing((open) => !open)}
                >
                    <Text className={labelText}>Edit</Text>
                </Pressable>
            </View>
            {offerOverride ? (
                <View testID={`${testID}-override`} className={panelClass}>
                    <Text className={labelText}>Approve anyway?</Text>
                    <Text className={bodyText}>
                        {`${refusal} Approving publishes this name as a followable organization.`}
                    </Text>
                    <View className="flex-row flex-wrap gap-2">
                        <Pressable
                            testID={`${testID}-override-confirm`}
                            variant="destructive"
                            disabled={approve.loading}
                            onPress={() => void submitApprove(true)}
                        >
                            <Text className={buttonText}>Approve anyway</Text>
                        </Pressable>
                        <Pressable
                            testID={`${testID}-override-cancel`}
                            variant="ghost"
                            onPress={() => setOverrideDismissed(true)}
                        >
                            <Text className={labelText}>Cancel</Text>
                        </Pressable>
                    </View>
                </View>
            ) : null}
            {refusal ? (
                <Text testID={`${testID}-error`} accessibilityRole="alert" className={errorText}>
                    {refusal}
                </Text>
            ) : null}
        </View>
    );
};

const ClaimedAffiliationsSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    if (billId === null) return null;

    const claims = (data.testimony_claimed_affiliations ?? []) as ClaimedAffiliation[];
    if (claims.length === 0) return null;

    const bill = (data.bill ?? {}) as {
        bill_llm_provisioning?: { generation_status?: string | null; has_testimony?: boolean } | null;
    };
    const generationStatus = bill.bill_llm_provisioning?.generation_status ?? null;
    const activeRun = (data.active_legislation_pipeline_run ?? null) as {
        status?: string | null;
        bill_id?: number | null;
    } | null;
    const cleanTestimonyRunning =
        activeRun?.status === "cleaning_testimony" && (activeRun.bill_id === null || activeRun.bill_id === billId);
    const coverage = (data.testimony_coverage ?? null) as { coverage_gap?: boolean; acknowledged?: boolean } | null;
    const guards: ApprovalGuards = {
        testimonyMissing: !bill.bill_llm_provisioning?.has_testimony,
        runInFlight: generationStatus === "pending" || generationStatus === "generating" || !!cleanTestimonyRunning,
        testimonyLeftOutUnacknowledged: !!coverage && !!coverage.coverage_gap && !coverage.acknowledged,
    };

    return (
        <View testID="admin-claimed-affiliations" className="px-4 mt-6 gap-3">
            {claims.map((claim) => (
                <ClaimedAffiliationCard
                    key={claim.position}
                    billId={billId}
                    claim={claim}
                    guards={guards}
                    refresh={refresh}
                />
            ))}
        </View>
    );
};

export default ClaimedAffiliationsSection;
