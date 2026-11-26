// @lat: [[mobile-bill-creator#Sections#The summary revisions section]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { apiClient } from "../../../api/client";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { exactTime } from "../../../utils/runTime";
import { Pressable } from "../../ui/Pressable";

interface SummaryRevision {
    id: number;
    summary_markdown: string;
    origin: string;
    actor_name?: string | null;
    llm_provider?: string | null;
    llm_model?: string | null;
    publication_role: "published" | "draft";
    review_state: string;
    news_source_snapshot_id?: number | null;
    has_snapshot?: boolean;
    created_at: string;
}

interface RevisionsResponse {
    summary_revisions?: SummaryRevision[];
}

interface RestoreResponse {
    revision?: SummaryRevision;
}

const RESTORED_NOTICE = "Bill summary restored.";
const RESTORED_AS_DRAFT_NOTICE =
    "Legacy revision restored as draft. Please review and declare news usage before publishing.";

const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const bodyText = "text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark";
const errorText = "text-xs font-open-sans-light text-destructive-light dark:text-destructive-dark";
const badgeText = `rounded border border-border-light dark:border-border-dark px-1.5 capitalize ${mutedText}`;
const panelClass = "gap-2 rounded-lg border border-border-light dark:border-border-dark p-3";

const ORIGIN_LABELS: Record<string, string> = {
    model_generation: "Model generation",
    operator_edit: "Operator edit",
    operator_paste: "Operator paste",
    restoration: "Restoration",
    initial_baseline: "Initial baseline",
};

const originLabel = (origin: string) => ORIGIN_LABELS[origin] ?? origin;

const provenanceLabel = (revision: SummaryRevision) => {
    if (revision.actor_name) return { text: `By ${revision.actor_name}`, known: true };
    if (revision.llm_provider || revision.llm_model) {
        const parts = [revision.llm_provider, revision.llm_model].filter(Boolean);
        return { text: `Model: ${parts.join(" / ")}`, known: true };
    }
    return { text: "Unknown provenance", known: false };
};

const hasSnapshot = (revision: SummaryRevision) => Boolean(revision.news_source_snapshot_id || revision.has_snapshot);

const timestamp = (revision: SummaryRevision) => exactTime(revision.created_at) ?? revision.created_at;

const RevisionRow: React.FC<{
    revision: SummaryRevision;
    isCurrent: boolean;
    isSelected: boolean;
    onInspect: () => void;
    onReviewDraft: () => void;
    onRestore: () => void;
}> = ({ revision, isCurrent, isSelected, onInspect, onReviewDraft, onRestore }) => {
    const provenance = provenanceLabel(revision);
    return (
        <View
            testID={`admin-summary-revision-${revision.id}`}
            className={`${panelClass} ${isSelected ? "border-primary-light dark:border-primary-dark" : ""}`}
        >
            <Text className={`font-mono ${mutedText}`}>{timestamp(revision)}</Text>
            <View className="flex-row flex-wrap gap-1">
                {isCurrent ? (
                    <Text testID={`admin-summary-revision-current-${revision.id}`} className={badgeText}>
                        Current
                    </Text>
                ) : null}
                <Text testID={`admin-summary-revision-role-${revision.id}`} className={badgeText}>
                    {revision.publication_role}
                </Text>
                <Text testID={`admin-summary-revision-review-${revision.id}`} className={badgeText}>
                    {revision.review_state}
                </Text>
                <Text testID={`admin-summary-revision-snapshot-${revision.id}`} className={badgeText}>
                    {hasSnapshot(revision) ? "Evidence snapshot" : "Legacy (no snapshot)"}
                </Text>
            </View>
            <Text className={bodyText}>
                <Text testID={`admin-summary-revision-origin-${revision.id}`} className={labelText}>
                    {originLabel(revision.origin)}
                </Text>
                {" • "}
                <Text
                    testID={
                        provenance.known
                            ? `admin-summary-revision-provenance-${revision.id}`
                            : "admin-summary-revision-unknown-provenance"
                    }
                    className={provenance.known ? mutedText : `italic ${mutedText}`}
                >
                    {provenance.text}
                </Text>
            </Text>
            <View className="flex-row flex-wrap gap-2">
                <Pressable testID={`admin-summary-revision-inspect-${revision.id}`} variant="ghost" onPress={onInspect}>
                    <Text className={labelText}>{isSelected ? "Hide preview" : "Inspect text"}</Text>
                </Pressable>
                {revision.publication_role === "draft" ? (
                    <Pressable
                        testID={`admin-summary-revision-review-draft-${revision.id}`}
                        variant="outline"
                        onPress={onReviewDraft}
                    >
                        <Text className={labelText}>Review draft</Text>
                    </Pressable>
                ) : (
                    <Pressable
                        testID={`admin-summary-revision-restore-${revision.id}`}
                        variant="outline"
                        disabled={isCurrent}
                        onPress={onRestore}
                    >
                        <Text className={labelText}>Restore</Text>
                    </Pressable>
                )}
            </View>
        </View>
    );
};

const RestoreConfirm: React.FC<{
    revision: SummaryRevision;
    restoring: boolean;
    errorMessage: string | null;
    onCancel: () => void;
    onConfirm: () => void;
}> = ({ revision, restoring, errorMessage, onCancel, onConfirm }) => {
    const snapshot = hasSnapshot(revision);
    return (
        <View testID="admin-summary-restore-confirm" className={panelClass}>
            <Text testID="admin-summary-restore-confirm-title" className={labelText}>
                {snapshot ? "Restore summary revision?" : "Restore legacy revision as review draft?"}
            </Text>
            <Text className={bodyText}>
                {snapshot
                    ? `This will restore the published summary to the version recorded on ${timestamp(revision)}. The current published summary will be retained in revision history.`
                    : "This historical revision has no evidence snapshot. Restoring it will create a review draft. You will need to review evidence and declare news usage before publishing."}
            </Text>
            <View testID="admin-summary-restore-confirm-details" className="gap-1">
                <Text className={mutedText}>Origin: {originLabel(revision.origin)}</Text>
                <Text className={mutedText}>Provenance: {provenanceLabel(revision).text}</Text>
                <Text className={mutedText}>Review state: {revision.review_state}</Text>
            </View>
            {errorMessage ? (
                <Text testID="admin-summary-restore-confirm-error" className={errorText}>
                    {errorMessage}
                </Text>
            ) : null}
            <View className="flex-row flex-wrap gap-2">
                <Pressable
                    testID="admin-summary-restore-confirm-cancel"
                    variant="outline"
                    disabled={restoring}
                    onPress={onCancel}
                >
                    <Text className={labelText}>Cancel</Text>
                </Pressable>
                <Pressable testID="admin-summary-restore-confirm-submit" disabled={restoring} onPress={onConfirm}>
                    <Text className={labelText}>
                        {restoring ? "Restoring…" : snapshot ? "Restore summary" : "Restore as review draft"}
                    </Text>
                </Pressable>
            </View>
        </View>
    );
};

const SummaryRevisionsPanel: React.FC<BillCreatorTabProps & { billId: number }> = ({
    billId,
    data,
    refresh,
    onReviewDraft,
}) => {
    const currentSummary = ((data.bill as { summary?: string | null } | undefined)?.summary ?? "") as string;
    const reviewDraft = (data.review_draft_revision ?? null) as SummaryRevision | null;

    const [open, setOpen] = useState(false);
    const [revisions, setRevisions] = useState<SummaryRevision[] | null>(null);
    const [loading, setLoading] = useState(false);
    const [loadFailed, setLoadFailed] = useState(false);
    const [selectedId, setSelectedId] = useState<number | null>(null);
    const [restoreTarget, setRestoreTarget] = useState<SummaryRevision | null>(null);
    const [refusedRestoreId, setRefusedRestoreId] = useState<number | null>(null);
    const [notice, setNotice] = useState<string | null>(null);
    const restore = useAdminMutation<RestoreResponse>("post", Routes.billRestoreSummaryRevision(billId));

    const load = async () => {
        setLoading(true);
        setLoadFailed(false);
        try {
            const response = await apiClient.get<RevisionsResponse>(Routes.adminBillCreatorSummaryRevisions(billId));
            setRevisions(response.summary_revisions ?? []);
        } catch {
            setLoadFailed(true);
        } finally {
            setLoading(false);
        }
    };

    const toggle = () => {
        setOpen(!open);
        if (!open && revisions === null && !loading) void load();
    };

    const confirmRestore = async () => {
        if (!restoreTarget) return;
        const response = await restore.run({ revision_id: restoreTarget.id, expected_summary: currentSummary });
        if (response === undefined) {
            setRefusedRestoreId(restoreTarget.id);
            return;
        }
        setRestoreTarget(null);
        setSelectedId(null);
        const restored = response?.revision;
        if (restored?.publication_role === "draft") {
            setNotice(RESTORED_AS_DRAFT_NOTICE);
            onReviewDraft?.(restored.id);
        } else {
            setNotice(RESTORED_NOTICE);
            await refresh();
        }
        void load();
    };

    const chooseRestoreTarget = (revision: SummaryRevision | null) => {
        setRefusedRestoreId(null);
        setRestoreTarget(revision);
    };

    const selected = revisions?.find((revision) => revision.id === selectedId) ?? null;
    const isCurrent = (revision: SummaryRevision) => revision.summary_markdown === currentSummary;

    return (
        <View testID="admin-summary-revisions" className="px-4 mt-6 gap-3">
            {reviewDraft ? (
                <View testID="admin-summary-revisions-draft" className={panelClass}>
                    <Text testID="admin-summary-revisions-draft-title" className={labelText}>
                        Historical draft loaded for review (#{reviewDraft.id})
                    </Text>
                    <Text className={bodyText}>
                        This historical revision was restored as a draft. Review the summary and declare news usage
                        before publishing. The live public summary remains unchanged.
                    </Text>
                    <Text testID="admin-summary-revisions-draft-text" className={`font-mono ${mutedText}`} selectable>
                        {reviewDraft.summary_markdown}
                    </Text>
                    <Pressable
                        testID="admin-summary-revisions-draft-close"
                        variant="outline"
                        onPress={() => onReviewDraft?.(null)}
                    >
                        <Text className={labelText}>Close draft</Text>
                    </Pressable>
                </View>
            ) : null}
            {notice ? (
                <Text testID="admin-summary-revisions-notice" className={bodyText}>
                    {notice}
                </Text>
            ) : null}
            <View className="flex-row flex-wrap gap-2">
                <Pressable
                    testID="admin-summary-revisions-toggle"
                    variant="outline"
                    accessibilityState={{ expanded: open }}
                    onPress={toggle}
                >
                    <Text className={labelText}>Summary revision history</Text>
                </Pressable>
                {open ? (
                    <Pressable
                        testID="admin-summary-revisions-refresh"
                        variant="outline"
                        disabled={loading}
                        onPress={() => void load()}
                    >
                        <Text className={labelText}>{loading ? "Refreshing…" : "Refresh history"}</Text>
                    </Pressable>
                ) : null}
            </View>
            {open ? (
                <View testID="admin-summary-revisions-content" className="gap-3">
                    {loading && revisions === null ? (
                        <Text testID="admin-summary-revisions-loading" className={mutedText}>
                            Loading revision history…
                        </Text>
                    ) : null}
                    {loadFailed ? (
                        <Text testID="admin-summary-revisions-error" className={errorText}>
                            Could not load the revision history — try again.
                        </Text>
                    ) : null}
                    {revisions !== null && revisions.length === 0 ? (
                        <Text className={mutedText}>No previous summary revisions recorded for this bill.</Text>
                    ) : null}
                    {revisions !== null && revisions.length > 0 ? (
                        <>
                            <View testID="admin-summary-revisions-list" className="gap-2">
                                {revisions.map((revision) => (
                                    <RevisionRow
                                        key={revision.id}
                                        revision={revision}
                                        isCurrent={isCurrent(revision)}
                                        isSelected={revision.id === selectedId}
                                        onInspect={() => setSelectedId(revision.id === selectedId ? null : revision.id)}
                                        onReviewDraft={() => onReviewDraft?.(revision.id)}
                                        onRestore={() => chooseRestoreTarget(revision)}
                                    />
                                ))}
                            </View>
                            <View testID="admin-summary-revisions-preview" className={panelClass}>
                                <Text testID="admin-summary-revisions-preview-title" className={labelText}>
                                    {selected
                                        ? `Historical preview: ${timestamp(selected)}`
                                        : "Current published summary"}
                                </Text>
                                <Text
                                    testID="admin-summary-revisions-preview-text"
                                    className={`font-mono ${mutedText}`}
                                    selectable
                                >
                                    {selected ? selected.summary_markdown : currentSummary || "(No published summary)"}
                                </Text>
                                {selected?.publication_role === "draft" ? (
                                    <Pressable
                                        testID="admin-summary-revisions-review-selected-draft"
                                        onPress={() => onReviewDraft?.(selected.id)}
                                    >
                                        <Text className={labelText}>Review draft</Text>
                                    </Pressable>
                                ) : selected ? (
                                    <Pressable
                                        testID="admin-summary-revisions-restore-selected"
                                        disabled={isCurrent(selected)}
                                        onPress={() => chooseRestoreTarget(selected)}
                                    >
                                        <Text className={labelText}>Restore this version</Text>
                                    </Pressable>
                                ) : null}
                            </View>
                        </>
                    ) : null}
                    {restoreTarget ? (
                        <RestoreConfirm
                            revision={restoreTarget}
                            restoring={restore.loading}
                            errorMessage={refusedRestoreId === restoreTarget.id ? restore.errorMessage : null}
                            onCancel={() => chooseRestoreTarget(null)}
                            onConfirm={() => void confirmRestore()}
                        />
                    ) : null}
                </View>
            ) : null}
        </View>
    );
};

const SummaryRevisionsSection: React.FC<BillCreatorTabProps> = (props) => {
    if (props.billId === null) {
        return (
            <View testID="admin-summary-revisions" className="px-4 mt-6">
                <Text className={mutedText}>Save this bill to see its summary revisions.</Text>
            </View>
        );
    }
    return <SummaryRevisionsPanel {...props} billId={props.billId} />;
};

export default SummaryRevisionsSection;
