// @lat: [[mobile-bill-creator#Sections#The campaign drafts section]]
import React, { useState } from "react";
import { Text, TextInput, View } from "react-native";

import { apiClient } from "../../../api/client";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { approvalBlockers, type ApprovalBlockers } from "./approvalBlockers";
import { Pressable } from "../../ui/Pressable";
import CampaignOrganizationLink, {
    type LinkableCampaign,
    type OrganizationCandidate,
} from "./CampaignOrganizationLink";

type Stance = "support" | "oppose" | "neutral";

interface CampaignDraft {
    content_hash: string;
    sender_count: number | null;
    letter_count: number;
    domain: string | null;
    rejected?: boolean;
    marked_individual?: boolean;
}

interface ApprovedCampaign extends LinkableCampaign {
    name: string | null;
    support: string;
    summary: string;
    source_campaign_draft_hash: string | null;
}

interface CampaignLetter {
    position: number;
    text: string;
    sender_address: string | null;
    sender_domain: string | null;
    repeat: boolean;
}

interface CampaignLetterBundle {
    content_hash: string;
    letters: CampaignLetter[];
}

interface LettersResponse {
    testimony_campaign_letters?: CampaignLetterBundle[];
}

interface WriteResponse {
    notice?: string;
}

type LettersState = "idle" | "loading" | "failed" | "loaded";

type CampaignWrite = "approve" | "reject" | "restore" | "markIndividual";

const STANCE_LABELS: Record<Stance, string> = { support: "Support", oppose: "Oppose", neutral: "Neutral" };
const STANCES: Stance[] = ["support", "oppose", "neutral"];

const SUPPORT_TO_STANCE: Record<string, Stance | undefined> = {
    FOR: "support",
    AGAINST: "oppose",
    ABSTAIN: "neutral",
};

const NAME_CLAMP_LENGTH = 120;

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const buttonText = "text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark";
const stampText = `rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";
const inputClass =
    "rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark";

const countNoun = (count: number, singular: string, plural: string) =>
    `${count.toLocaleString()} ${count === 1 ? singular : plural}`;

const unnamedLine = (senderCount: number | null) =>
    senderCount === null ? "This letter" : `${countNoun(senderCount, "person", "people")} sent this letter`;

const senderLabel = (letter: CampaignLetter) => letter.sender_address || letter.sender_domain || "Unknown sender";

interface LetterListProps {
    testID: string;
    letters: CampaignLetter[] | undefined;
    letterCount: number;
    state: LettersState;
    onRequest: () => void;
}

// @lat: [[campaign-letter-disclosure#Why the disclosure is gated on the count rather than the letters]]
const LetterList: React.FC<LetterListProps> = ({ testID, letters, letterCount, state, onRequest }) => {
    const [expanded, setExpanded] = useState(false);
    const [page, setPage] = useState(0);

    if (letterCount === 0) return null;

    const toggle = () => {
        setExpanded(!expanded);
        if (!expanded && state === "idle") onRequest();
    };

    const pageCount = letters?.length ?? 0;
    const current = pageCount > 0 ? letters?.[Math.min(page, pageCount - 1)] : undefined;

    return (
        <View className="gap-2">
            <Pressable testID={`${testID}-letters-toggle`} variant="ghost" onPress={toggle}>
                <Text className={labelText}>
                    {expanded ? "Hide letters" : `Show ${countNoun(letterCount, "letter", "letters")}`}
                </Text>
            </Pressable>
            {expanded && state === "loading" ? (
                <Text testID={`${testID}-letters-loading`} className={mutedText}>
                    Loading letters…
                </Text>
            ) : null}
            {expanded && state === "failed" ? (
                <View testID={`${testID}-letters-error`} className="gap-2">
                    <Text className={mutedText}>The letters could not be loaded.</Text>
                    <Pressable testID={`${testID}-letters-retry`} variant="outline" onPress={onRequest}>
                        <Text className={labelText}>Try again</Text>
                    </Pressable>
                </View>
            ) : null}
            {expanded && state === "loaded" && !current ? (
                <Text testID={`${testID}-letters-empty`} className={mutedText}>
                    No letter text could be produced for this campaign.
                </Text>
            ) : null}
            {expanded && current ? (
                <View className="gap-2">
                    <View testID={`${testID}-letter`} className={panelClass}>
                        <View className="flex-row flex-wrap items-center gap-2">
                            <Text className={labelText}>{`Letter #${current.position}`}</Text>
                            <Text className={mutedText}>{senderLabel(current)}</Text>
                            {current.repeat ? <Text className={stampText}>DUPLICATE</Text> : null}
                        </View>
                        <Text selectable className={bodyText}>
                            {current.text}
                        </Text>
                    </View>
                    <View className="flex-row items-center gap-2">
                        <Pressable
                            testID={`${testID}-letter-previous`}
                            variant="outline"
                            disabled={page === 0}
                            onPress={() => setPage(page - 1)}
                        >
                            <Text className={labelText}>Previous</Text>
                        </Pressable>
                        <Text testID={`${testID}-letter-page`} className={mutedText}>
                            {`${Math.min(page, pageCount - 1) + 1} of ${pageCount}`}
                        </Text>
                        <Pressable
                            testID={`${testID}-letter-next`}
                            variant="outline"
                            disabled={page >= pageCount - 1}
                            onPress={() => setPage(page + 1)}
                        >
                            <Text className={labelText}>Next</Text>
                        </Pressable>
                    </View>
                </View>
            ) : null}
        </View>
    );
};

interface CampaignDraftCardProps {
    billId: number;
    draft: CampaignDraft;
    approved: ApprovedCampaign | undefined;
    organizationCandidates: OrganizationCandidate[];
    letters: CampaignLetter[] | undefined;
    lettersState: LettersState;
    onRequestLetters: () => void;
    guards: ApprovalBlockers;
    refresh: () => Promise<void>;
}

// @lat: [[campaign-position-cards]]
const CampaignDraftCard: React.FC<CampaignDraftCardProps> = ({
    billId,
    draft,
    approved,
    organizationCandidates,
    letters,
    lettersState,
    onRequestLetters,
    guards,
    refresh,
}) => {
    const testID = `admin-campaign-draft-${draft.content_hash}`;
    const approve = useAdminMutation<WriteResponse>("post", Routes.billCampaigns(billId));
    const reject = useAdminMutation<WriteResponse>("post", Routes.billRejectCampaignDraft(billId));
    const restore = useAdminMutation<WriteResponse>("post", Routes.billRestoreCampaignDraft(billId));
    const markIndividual = useAdminMutation<WriteResponse>("post", Routes.billMarkIndividualCampaignDraft(billId));

    const [editing, setEditing] = useState(false);
    const [nameExpanded, setNameExpanded] = useState(false);
    const [lastWrite, setLastWrite] = useState<CampaignWrite | null>(null);
    const [notice, setNotice] = useState<string | null>(null);

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#An unnamed campaign is a complete record]]
    const serverName = approved?.name ?? "";
    const serverStance = SUPPORT_TO_STANCE[approved?.support ?? ""] ?? "support";
    const serverSummary = approved?.summary ?? "";
    const [lastServerName, setLastServerName] = useState(serverName);
    const [lastServerStance, setLastServerStance] = useState<Stance>(serverStance);
    const [lastServerSummary, setLastServerSummary] = useState(serverSummary);
    const [name, setName] = useState(serverName);
    const [stance, setStance] = useState<Stance>(serverStance);
    const [summary, setSummary] = useState(serverSummary);

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

    const writes = { approve, reject, restore, markIndividual };
    const submitting = approve.loading || reject.loading || restore.loading || markIndividual.loading;

    const submit = async (write: CampaignWrite, body: Record<string, unknown>) => {
        setLastWrite(write);
        setNotice(null);
        const response = await writes[write].run(body);
        if (response === undefined) return;
        setNotice(response?.notice ?? null);
        await refresh();
    };

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#The draft's content hash is its whole identity]]
    const submitApprove = () => submit("approve", { name, support: stance, summary, content_hash: draft.content_hash });
    // @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
    const submitDecision = (write: CampaignWrite) => submit(write, { content_hash: draft.content_hash });

    const failedWrite = lastWrite ? writes[lastWrite] : null;
    const reason = failedWrite?.fieldErrors?.campaign_position;
    const refusal = typeof reason === "string" && reason.trim() !== "" ? reason : (failedWrite?.errorMessage ?? null);

    const messages = (
        <>
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
        </>
    );

    const persistedNameLine = (approved?.name ?? "").trim() || unnamedLine(draft.sender_count);
    const evidenceParts = [
        countNoun(draft.sender_count ?? 0, "sender", "senders"),
        countNoun(draft.letter_count, "letter", "letters"),
    ];
    if (draft.domain) evidenceParts.push(`sent through ${draft.domain}`);
    const evidenceSubline = evidenceParts.join(" · ");

    const restoreRow = (stamp: string, line: string) => (
        <View testID={testID} className={panelClass}>
            <View className="flex-row flex-wrap items-center justify-between gap-2">
                <View className="flex-1 flex-row items-center gap-2">
                    <Text className={stampText}>{stamp}</Text>
                    <Text testID={`${testID}-name`} numberOfLines={1} className={`flex-1 ${mutedText}`}>
                        {line}
                    </Text>
                </View>
                <Pressable
                    testID={`${testID}-restore`}
                    variant="outline"
                    disabled={submitting}
                    onPress={() => void submitDecision("restore")}
                >
                    <Text className={labelText}>Restore</Text>
                </Pressable>
            </View>
            {messages}
        </View>
    );

    // @lat: [[campaign-draft-rejection#Why a rejected card stays visible]]
    if (draft.rejected) return restoreRow("REJECTED", persistedNameLine);
    // @lat: [[campaign-position-cards#Marking false-positive campaign drafts as individual letters]]
    if (draft.marked_individual && !approved) {
        return restoreRow("INDIVIDUAL LETTERS", `${persistedNameLine} · ${evidenceSubline}`);
    }

    const nameLine = name.trim() || unnamedLine(draft.sender_count);
    const nameIsLong = nameLine.length > NAME_CLAMP_LENGTH;

    // @lat: [[campaign-approval-guard-chain#Why summary validation runs first]]
    const summaryMissing = summary.trim().length === 0;
    const approveDisabled =
        submitting ||
        summaryMissing ||
        guards.testimonyMissing ||
        guards.runInFlight ||
        guards.testimonyLeftOutUnacknowledged;

    return (
        <View testID={testID} className={panelClass}>
            <View className="flex-row flex-wrap items-center justify-between gap-2">
                <View className="flex-1">
                    <Text
                        testID={`${testID}-name`}
                        numberOfLines={nameIsLong && !nameExpanded ? 1 : undefined}
                        className={labelText}
                    >
                        {nameLine}
                    </Text>
                    {nameIsLong ? (
                        <Pressable variant="ghost" onPress={() => setNameExpanded(!nameExpanded)}>
                            <Text className={labelText}>{nameExpanded ? "Show less" : "Show full name"}</Text>
                        </Pressable>
                    ) : null}
                </View>
                <View className="flex-row items-center gap-2">
                    {approved ? <Text className={stampText}>APPROVED</Text> : null}
                    <Text className={stampText}>CAMPAIGN</Text>
                </View>
            </View>
            <Text testID={`${testID}-evidence`} className={mutedText}>
                {evidenceSubline}
            </Text>
            <LetterList
                testID={testID}
                letters={letters}
                letterCount={draft.letter_count}
                state={lettersState}
                onRequest={onRequestLetters}
            />
            <Text className={mutedText}>Approving records a campaign position. It never creates an organization.</Text>
            {approved ? (
                <CampaignOrganizationLink
                    billId={billId}
                    campaign={approved}
                    candidates={organizationCandidates}
                    runInFlight={guards.runInFlight}
                    refresh={refresh}
                />
            ) : null}
            {editing ? (
                <View className="gap-2">
                    <Text className={mutedText}>Campaign name</Text>
                    <TextInput
                        testID={`${testID}-edit-name`}
                        value={name}
                        onChangeText={setName}
                        accessibilityLabel="Campaign name"
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
                        disabled={submitting}
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
                    onPress={() => void submitApprove()}
                >
                    <Text className={buttonText}>{approved ? "Update this campaign" : "Approve as this campaign"}</Text>
                </Pressable>
                <Pressable
                    testID={`${testID}-reject`}
                    variant="outline"
                    disabled={submitting}
                    onPress={() => void submitDecision("reject")}
                >
                    <Text className={labelText}>Reject</Text>
                </Pressable>
                {!approved ? (
                    <Pressable
                        testID={`${testID}-mark-individual`}
                        variant="outline"
                        disabled={submitting}
                        onPress={() => void submitDecision("markIndividual")}
                    >
                        <Text className={labelText}>Mark as Individual Letters</Text>
                    </Pressable>
                ) : null}
                <Pressable
                    testID={`${testID}-edit`}
                    variant="ghost"
                    disabled={submitting}
                    onPress={() => setEditing(!editing)}
                >
                    <Text className={labelText}>Edit</Text>
                </Pressable>
            </View>
            {messages}
        </View>
    );
};

const CampaignDraftsSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const [letterBundles, setLetterBundles] = useState<Map<string, CampaignLetter[]> | null>(null);
    const [lettersState, setLettersState] = useState<LettersState>("idle");

    if (billId === null) return null;

    const drafts = (data.testimony_campaign_drafts ?? []) as CampaignDraft[];
    if (drafts.length === 0) return null;

    const campaigns = (data.campaigns ?? []) as ApprovedCampaign[];
    const candidatesByCampaignId = (data.campaign_organization_candidates ?? {}) as Record<
        string,
        OrganizationCandidate[] | undefined
    >;
    const guards = approvalBlockers(data, billId);

    // @lat: [[campaign-letter-disclosure#Why the list asks for its own letters]]
    const requestLetters = async () => {
        if (lettersState === "loading") return;
        setLettersState("loading");
        try {
            const response = await apiClient.get<LettersResponse>(Routes.adminBillCreatorCampaignLetters(billId));
            const bundles = response.testimony_campaign_letters ?? [];
            setLetterBundles(new Map(bundles.map((bundle) => [bundle.content_hash, bundle.letters])));
            setLettersState("loaded");
        } catch {
            setLettersState("failed");
        }
    };

    return (
        <View testID="admin-campaign-drafts" className="px-4 mt-6 gap-3">
            {drafts.map((draft, index) => {
                const approvedCampaign = campaigns.find(
                    (campaign) => campaign.source_campaign_draft_hash === draft.content_hash,
                );
                return (
                    <CampaignDraftCard
                        key={draft.content_hash || index}
                        billId={billId}
                        draft={draft}
                        approved={approvedCampaign}
                        organizationCandidates={(approvedCampaign && candidatesByCampaignId[approvedCampaign.id]) || []}
                        letters={letterBundles?.get(draft.content_hash)}
                        lettersState={lettersState}
                        onRequestLetters={() => void requestLetters()}
                        guards={guards}
                        refresh={refresh}
                    />
                );
            })}
        </View>
    );
};

export default CampaignDraftsSection;
