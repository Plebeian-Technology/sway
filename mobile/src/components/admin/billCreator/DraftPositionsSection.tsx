// @lat: [[mobile-bill-creator#Sections#The draft positions section]]
import React, { useMemo, useState } from "react";
import { Linking, Text, TextInput, View } from "react-native";

import { Routes } from "../../../api/routes";
import { useAdminMutation, type UseAdminMutationResult } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { usePolling } from "../../../hooks/admin/usePolling";
import { isSafeCitationUrl } from "../../../utils/safeUrl";
import { Pressable } from "../../ui/Pressable";
import { approvalBlockers } from "./approvalBlockers";

type Stance = "support" | "oppose" | "neutral";

interface DraftPosition {
    org_name: string;
    stance: string;
    summary: string | null;
    draft_token?: string;
    evidence_retracted_at?: string | null;
    rejected?: boolean;
    bill_news_article_id?: number | null;
    text_version_id?: number | null;
    evidence_excerpt?: string | null;
    speaker_name?: string | null;
    speaker_role?: string | null;
    source_url?: string | null;
    outlet_name?: string | null;
    article_title?: string | null;
    excerpt_page?: number | null;
    excerpt_paragraph?: number | null;
    excerpt_offset?: number | null;
}

interface PositionsBill {
    bill_llm_provisioning?: {
        generation_status?: string | null;
        has_testimony?: boolean;
        reclaimable?: boolean;
        draft_org_positions?: DraftPosition[] | null;
    } | null;
    bill_pipeline_refresh?: { status?: string | null } | null;
}

const POLL_INTERVAL_MS = 5000;
const TERMINAL_RUN_STATUSES = ["completed", "succeeded", "partial", "failed", "cancelled"];

const STANCE_LABELS: Record<Stance, string> = { support: "Support", oppose: "Oppose", neutral: "Neutral" };
const STANCE_OPTIONS: Stance[] = ["support", "oppose", "neutral"];

const NOTHING_GENERATED =
    "No public testimony available for this bill — positions are not generated without testimony. " +
    "Fill in the Supplemental testimony field on this tab and click Save testimony to enable generation.";
const DRAFTS_RETRACTED =
    "No public testimony available for this bill — the draft positions below were drawn from testimony that has " +
    "been withdrawn, so they cannot be approved. Pasting testimony back does not restore them: regenerate the " +
    "positions once testimony is available, or reject them.";
const DRAFTS_UNAPPROVABLE =
    "No public testimony available for this bill — the draft positions below were drawn from testimony that is no " +
    "longer on file, so they cannot be approved. Paste the testimony back into the Supplemental testimony field on " +
    "this tab and click Save testimony, or reject them.";
const EVIDENCE_RETRACTED =
    "The testimony this draft was drawn from is no longer on this bill, so it cannot be approved. " +
    "Regenerate the positions once testimony is available, or reject this draft.";

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const stampText = `rounded border border-border-light dark:border-border-dark px-1.5 ${mutedText}`;
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";
const inputClass =
    "rounded-md border border-border-light bg-input-light px-4 py-3 font-open-sans-light text-foreground-light dark:border-border-dark dark:bg-input-dark dark:text-foreground-dark";

const isNewsSourced = (draft: DraftPosition) =>
    (draft.bill_news_article_id !== null && draft.bill_news_article_id !== undefined) ||
    (draft.text_version_id !== null && draft.text_version_id !== undefined) ||
    Boolean(draft.evidence_excerpt);

const stanceLabel = (stance: string) =>
    stance in STANCE_LABELS ? STANCE_LABELS[stance as Stance] : stance || "No position";

const cardKeys = (drafts: DraftPosition[]) => {
    const seen = new Map<string, number>();
    return drafts.map((draft) => {
        const identity = draft.draft_token ?? `${draft.org_name} ${draft.stance} ${draft.summary}`;
        const occurrence = seen.get(identity) ?? 0;
        seen.set(identity, occurrence + 1);
        return `${identity}#${occurrence}`;
    });
};

const refusalOf = (mutation: UseAdminMutationResult<unknown>) => {
    if (mutation.errorMessage === null) return null;
    const reason = mutation.fieldErrors?.org_position;
    return typeof reason === "string" && reason.trim() !== "" ? reason : mutation.errorMessage;
};

interface RunInFlightNoticeProps {
    summaryRunInFlight: boolean;
    cleanTestimonyRunning: boolean;
    draftCount: number;
    abandoned: boolean;
}

const RunInFlightNotice: React.FC<RunInFlightNoticeProps> = ({
    summaryRunInFlight,
    cleanTestimonyRunning,
    draftCount,
    abandoned,
}) => {
    if (!summaryRunInFlight && !cleanTestimonyRunning) return null;
    const cleaningOnly = cleanTestimonyRunning && !summaryRunInFlight;
    const held =
        draftCount > 0
            ? `You are looking at ${draftCount} draft position${draftCount === 1 ? "" : "s"} already on this bill. `
            : "";
    const title = cleaningOnly
        ? "The testimony behind these positions is being rewritten"
        : abandoned
          ? "Nothing is working on this row"
          : "A new set of draft positions is on the way";
    const description = cleaningOnly
        ? "A clean-testimony run is regrouping the letters these drafts were written from. Approve is off " +
          "while this row is queued or running. It comes back when the run finishes."
        : abandoned
          ? "Approve is off while this row is queued or running. It comes back when Sway releases the " +
            "run, which changes no drafts."
          : "The new run replaces them when it finishes. Approve is off while this row is queued or " +
            "running. It comes back when the run finishes.";
    return (
        <View testID="admin-draft-positions-run-in-flight" className={panelClass}>
            <Text className={labelText}>{title}</Text>
            <Text className={bodyText}>{`${held}${description}`}</Text>
        </View>
    );
};

interface DraftPositionCardProps {
    billId: number;
    index: number;
    draft: DraftPosition;
    testimonyMissing: boolean;
    runInFlight: boolean;
    testimonyLeftOutUnacknowledged: boolean;
    refresh: () => Promise<void>;
}

const DraftPositionCard: React.FC<DraftPositionCardProps> = ({
    billId,
    index,
    draft,
    testimonyMissing,
    runInFlight,
    testimonyLeftOutUnacknowledged,
    refresh,
}) => {
    const testID = `admin-draft-position-${index}`;
    const approve = useAdminMutation<unknown>("post", Routes.billApproveOrgPosition(billId));
    const reject = useAdminMutation<unknown>("patch", Routes.adminBillDraftOrgPosition(billId, index));

    const [orgName, setOrgName] = useState(draft.org_name);
    const [stance, setStance] = useState(draft.stance);
    const [summary, setSummary] = useState(draft.summary ?? "");
    const [editing, setEditing] = useState(false);
    const [nameDraft, setNameDraft] = useState("");
    const [stanceDraft, setStanceDraft] = useState("");
    const [summaryDraft, setSummaryDraft] = useState("");
    const [overrideSent, setOverrideSent] = useState(false);
    const [overrideDismissed, setOverrideDismissed] = useState(false);

    const submitting = approve.loading || reject.loading;
    const newsSourced = isNewsSourced(draft);
    const evidenceRetracted = !!draft.evidence_retracted_at;
    const approveDisabled =
        evidenceRetracted ||
        (!newsSourced && testimonyMissing) ||
        runInFlight ||
        (!newsSourced && testimonyLeftOutUnacknowledged);

    const submitApprove = async (overridePrivateIndividual: boolean) => {
        setOverrideSent(overridePrivateIndividual);
        setOverrideDismissed(false);
        const response = await approve.run({
            org_name: orgName,
            support: stance,
            summary,
            index,
            draft_org_name: draft.org_name,
            draft_token: draft.draft_token,
            ...(overridePrivateIndividual ? { override_private_individual: true } : {}),
        });
        if (response !== undefined) await refresh();
    };

    const submitReject = async () => {
        const response = await reject.run({
            rejected: true,
            draft_org_name: draft.org_name,
            draft_token: draft.draft_token,
        });
        if (response !== undefined) await refresh();
    };

    const startEdit = () => {
        setNameDraft(orgName);
        setStanceDraft(stance);
        setSummaryDraft(summary);
        setEditing(true);
    };

    const applyEdit = () => {
        setOrgName(nameDraft);
        setStance(stanceDraft);
        setSummary(summaryDraft);
        setEditing(false);
    };

    const approveRefusal = refusalOf(approve);
    const offerOverride =
        approve.fieldErrors?.private_individual_refusal === true && !overrideSent && !overrideDismissed;
    const refusal = offerOverride ? refusalOf(reject) : (approveRefusal ?? refusalOf(reject));

    const locator = [
        draft.excerpt_page !== null && draft.excerpt_page !== undefined ? `p. ${draft.excerpt_page}` : null,
        draft.excerpt_paragraph !== null && draft.excerpt_paragraph !== undefined
            ? `para. ${draft.excerpt_paragraph}`
            : null,
        draft.excerpt_offset !== null && draft.excerpt_offset !== undefined ? `char ${draft.excerpt_offset}` : null,
    ]
        .filter(Boolean)
        .join(", ");
    const sourceLabel = draft.outlet_name || draft.article_title || draft.source_url || "";
    const sourceUrl = draft.source_url ?? null;

    return (
        <View testID={testID} className={panelClass}>
            <View className="flex-row flex-wrap items-center justify-between gap-2">
                <Text testID={`${testID}-name`} className={labelText}>
                    {orgName}
                </Text>
                <Text testID={`${testID}-stance`} className={stampText}>
                    {stanceLabel(stance)}
                </Text>
            </View>
            <Text testID={`${testID}-summary`} className={bodyText}>
                {summary}
            </Text>
            {draft.evidence_excerpt ? (
                <View
                    testID={`${testID}-excerpt`}
                    className="gap-1 border-l-2 border-border-light dark:border-border-dark pl-3"
                >
                    <Text className={bodyText}>{`“${draft.evidence_excerpt}”`}</Text>
                    <View className="flex-row flex-wrap gap-2">
                        {draft.speaker_name || draft.speaker_role ? (
                            <Text className={mutedText}>
                                {`— ${[draft.speaker_name, draft.speaker_role].filter(Boolean).join(", ")}`}
                            </Text>
                        ) : null}
                        {sourceUrl !== null && isSafeCitationUrl(sourceUrl) ? (
                            <Text
                                testID={`${testID}-source`}
                                accessibilityRole="link"
                                className="text-xs font-open-sans-semibold text-primary-light dark:text-primary-dark"
                                onPress={() => void Linking.openURL(sourceUrl).catch(() => {})}
                            >
                                {sourceLabel}
                            </Text>
                        ) : sourceUrl ? (
                            <Text testID={`${testID}-source`} className={mutedText}>
                                {sourceLabel}
                            </Text>
                        ) : null}
                        {locator ? <Text className={mutedText}>{locator}</Text> : null}
                    </View>
                </View>
            ) : null}
            {evidenceRetracted ? (
                <Text testID={`${testID}-retracted`} className={bodyText}>
                    {EVIDENCE_RETRACTED}
                </Text>
            ) : null}
            {editing ? (
                <View className="gap-2">
                    <Text className={mutedText}>Organization name</Text>
                    <TextInput
                        testID={`${testID}-edit-name`}
                        value={nameDraft}
                        onChangeText={setNameDraft}
                        accessibilityLabel="Organization name"
                        className={inputClass}
                        style={{ minHeight: 44 }}
                    />
                    <Text className={mutedText}>Position</Text>
                    <View className="flex-row flex-wrap gap-2">
                        {STANCE_OPTIONS.map((option) => (
                            <Pressable
                                key={option}
                                testID={`${testID}-edit-stance-${option}`}
                                variant={stanceDraft === option ? "default" : "outline"}
                                accessibilityRole="radio"
                                accessibilityState={{ selected: stanceDraft === option }}
                                accessibilityLabel={STANCE_LABELS[option]}
                                onPress={() => setStanceDraft(option)}
                            >
                                <Text className={labelText}>{STANCE_LABELS[option]}</Text>
                            </Pressable>
                        ))}
                    </View>
                    <Text className={mutedText}>Summary</Text>
                    <TextInput
                        testID={`${testID}-edit-summary`}
                        value={summaryDraft}
                        onChangeText={setSummaryDraft}
                        multiline
                        numberOfLines={3}
                        accessibilityLabel="Summary"
                        className={inputClass}
                        style={{ minHeight: 88, textAlignVertical: "top" }}
                    />
                    <Text className={mutedText}>
                        Edits stay on this card until Approve sends them. Reject discards the draft.
                    </Text>
                    <View className="flex-row flex-wrap gap-2">
                        <Pressable testID={`${testID}-apply`} variant="default" onPress={applyEdit}>
                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                Apply edits
                            </Text>
                        </Pressable>
                        <Pressable testID={`${testID}-cancel`} variant="ghost" onPress={() => setEditing(false)}>
                            <Text className={labelText}>Cancel edit</Text>
                        </Pressable>
                    </View>
                </View>
            ) : (
                <View className="flex-row flex-wrap gap-2">
                    <Pressable
                        testID={`${testID}-approve`}
                        variant="default"
                        disabled={submitting || approveDisabled}
                        accessibilityLabel={`Approve ${orgName}`}
                        onPress={() => void submitApprove(false)}
                    >
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            Approve
                        </Text>
                    </Pressable>
                    <Pressable
                        testID={`${testID}-reject`}
                        variant="outline"
                        disabled={submitting}
                        accessibilityLabel={`Reject ${orgName}`}
                        onPress={() => void submitReject()}
                    >
                        <Text className={labelText}>Reject</Text>
                    </Pressable>
                    <Pressable
                        testID={`${testID}-edit`}
                        variant="ghost"
                        disabled={submitting}
                        accessibilityLabel={`Edit ${orgName}`}
                        onPress={startEdit}
                    >
                        <Text className={labelText}>Edit</Text>
                    </Pressable>
                </View>
            )}
            {offerOverride ? (
                <View testID={`${testID}-override`} className={panelClass}>
                    <Text className={labelText}>Approve anyway?</Text>
                    <Text className={bodyText}>
                        {`${approveRefusal} Approving publishes this name as a followable organization.`}
                    </Text>
                    <View className="flex-row flex-wrap gap-2">
                        <Pressable
                            testID={`${testID}-override-confirm`}
                            variant="destructive"
                            disabled={submitting}
                            onPress={() => void submitApprove(true)}
                        >
                            <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                Approve anyway
                            </Text>
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

const DraftPositionsSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const bill = (data.bill ?? {}) as PositionsBill;
    const provisioning = bill.bill_llm_provisioning ?? null;
    const pipelineStatus = bill.bill_pipeline_refresh?.status ?? null;
    const pipelineBusy = pipelineStatus !== null && !TERMINAL_RUN_STATUSES.includes(pipelineStatus);
    const { summaryRunInFlight, cleanTestimonyRunning, runInFlight, testimonyMissing, testimonyLeftOutUnacknowledged } =
        approvalBlockers(data, billId);

    // @lat: [[mobile-bill-creator#Sections#The draft positions section#Polling while a run is in flight]]
    usePolling(refresh, billId !== null && (summaryRunInFlight || pipelineBusy), POLL_INTERVAL_MS);

    const drafts = useMemo(
        () =>
            (provisioning?.draft_org_positions ?? [])
                .map((draft, rawIndex) => ({ draft, rawIndex }))
                .filter(({ draft }) => !draft.rejected),
        [provisioning?.draft_org_positions],
    );
    const keys = useMemo(() => cardKeys(drafts.map(({ draft }) => draft)), [drafts]);

    if (billId === null) return null;

    const hasDrafts = drafts.length > 0;
    const allDraftsRetracted = hasDrafts && drafts.every(({ draft }) => !!draft.evidence_retracted_at);
    const allNewsSourced = hasDrafts && drafts.every(({ draft }) => isNewsSourced(draft));

    return (
        <View testID="admin-draft-positions" className="px-4 mt-6 gap-3">
            <Text accessibilityRole="header" className={labelText}>
                Draft positions
            </Text>
            <RunInFlightNotice
                summaryRunInFlight={summaryRunInFlight}
                cleanTestimonyRunning={cleanTestimonyRunning}
                draftCount={drafts.length}
                abandoned={!!provisioning?.reclaimable}
            />
            {testimonyMissing && !allNewsSourced ? (
                <Text testID="admin-draft-positions-no-testimony" className={hasDrafts ? bodyText : mutedText}>
                    {hasDrafts ? (allDraftsRetracted ? DRAFTS_RETRACTED : DRAFTS_UNAPPROVABLE) : NOTHING_GENERATED}
                </Text>
            ) : null}
            {!hasDrafts && !testimonyMissing ? (
                <Text testID="admin-draft-positions-empty" className={mutedText}>
                    No draft positions generated.
                </Text>
            ) : null}
            {drafts.map(({ draft, rawIndex }, i) => (
                <DraftPositionCard
                    key={keys[i]}
                    billId={billId}
                    index={rawIndex}
                    draft={draft}
                    testimonyMissing={testimonyMissing}
                    runInFlight={runInFlight}
                    testimonyLeftOutUnacknowledged={testimonyLeftOutUnacknowledged}
                    refresh={refresh}
                />
            ))}
        </View>
    );
};

export default DraftPositionsSection;
