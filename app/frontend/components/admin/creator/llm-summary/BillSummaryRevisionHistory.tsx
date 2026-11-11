import { router } from "@inertiajs/react";
import { ChevronDown, ChevronUp, History, Loader2, RotateCcw } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";
import { useBillSummaryRevisions } from "app/frontend/components/admin/creator/llm-summary/useBillSummaryRevisions";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";

interface IProps {
    billId: number;
    currentSummary: string;
    onSelectDraft?: (draft: IBillSummaryRevision) => void;
}

const originLabel = (origin: IBillSummaryRevision["origin"]): string => {
    switch (origin) {
        case "model_generation":
            return "Model generation";
        case "operator_edit":
            return "Operator edit";
        case "operator_paste":
            return "Operator paste";
        case "restoration":
            return "Restoration";
        case "initial_baseline":
            return "Initial baseline";
        default:
            return origin;
    }
};

const provenanceLabel = (rev: IBillSummaryRevision): { text: string; isKnown: boolean } => {
    if (rev.actor_name) {
        return { text: `By ${rev.actor_name}`, isKnown: true };
    }
    if (rev.llm_provider || rev.llm_model) {
        const parts = [rev.llm_provider, rev.llm_model].filter(Boolean);
        return { text: `Model: ${parts.join(" / ")}`, isKnown: true };
    }
    return { text: "Unknown provenance", isKnown: false };
};

// @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
const BillSummaryRevisionHistory: React.FC<IProps> = ({ billId, currentSummary, onSelectDraft }) => {
    const { revisions, loading, load: reloadRevisions } = useBillSummaryRevisions();
    const [isOpen, setIsOpen] = useState<boolean>(false);
    const [selectedRevisionId, setSelectedRevisionId] = useState<number | null>(null);
    const [restoreTarget, setRestoreTarget] = useState<IBillSummaryRevision | null>(null);
    const [isRestoring, setIsRestoring] = useState<boolean>(false);

    useEffect(() => {
        if (isOpen && revisions === null && !loading) {
            reloadRevisions();
        }
    }, [isOpen, revisions, loading, reloadRevisions]);

    const handleReviewDraft = useCallback(
        (rev: IBillSummaryRevision) => {
            if (onSelectDraft) {
                onSelectDraft(rev);
            } else {
                router.get(
                    `/admin/bill_creator/${billId}/summary`,
                    { draft_revision_id: rev.id },
                    { preserveScroll: true },
                );
            }
        },
        [billId, onSelectDraft],
    );

    const handleToggleOpen = useCallback(() => {
        const next = !isOpen;
        setIsOpen(next);
        if (next && revisions === null && !loading) {
            reloadRevisions();
        }
    }, [isOpen, revisions, loading, reloadRevisions]);

    const handleConfirmRestore = useCallback(() => {
        if (!restoreTarget) return;

        setIsRestoring(true);
        router.post(
            `/bills/${billId}/restore_summary_revision`,
            {
                revision_id: restoreTarget.id,
                expected_summary: currentSummary,
            },
            {
                preserveScroll: true,
                onFinish: () => {
                    setIsRestoring(false);
                    setRestoreTarget(null);
                },
            },
        );
    }, [billId, currentSummary, restoreTarget]);

    const selectedRevision = revisions?.find((r) => r.id === selectedRevisionId) ?? null;

    return (
        <div data-testid="bill-summary-revision-history" className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
                <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    data-testid="toggle-revision-history"
                    onClick={handleToggleOpen}
                    className="flex items-center gap-2 px-2 text-sm font-medium text-foreground hover:bg-muted"
                >
                    <History className="size-4" />
                    <span>Summary revision history</span>
                    {isOpen ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}
                </Button>
                {isOpen && (
                    <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        disabled={loading}
                        onClick={reloadRevisions}
                        data-testid="btn-reload-revisions"
                        className="text-xs"
                    >
                        {loading ? <Loader2 className="size-3 animate-spin mr-1" /> : null}
                        Refresh history
                    </Button>
                )}
            </div>

            {isOpen && (
                <div
                    data-testid="revision-history-content"
                    className="flex flex-col gap-4 rounded-lg border border-border-soft bg-muted/30 p-4"
                >
                    {loading && revisions === null && (
                        <div
                            data-testid="revisions-loading"
                            className="flex items-center gap-2 py-4 text-sm text-muted-foreground"
                        >
                            <Loader2 className="size-4 animate-spin" />
                            <span>Loading revision history…</span>
                        </div>
                    )}

                    {revisions !== null && revisions.length === 0 && (
                        <p data-testid="revisions-empty" className="py-2 text-sm text-muted-foreground">
                            No previous summary revisions recorded for this bill.
                        </p>
                    )}

                    {revisions !== null && revisions.length > 0 && (
                        <div className="grid gap-4 md:grid-cols-2">
                            <div
                                data-testid="revisions-list"
                                className="flex flex-col gap-2 max-h-96 overflow-y-auto pr-1"
                            >
                                {revisions.map((rev) => {
                                    const prov = provenanceLabel(rev);
                                    const isCurrent = rev.summary_markdown === currentSummary;
                                    const isSelected = rev.id === selectedRevisionId;

                                    return (
                                        <div
                                            key={rev.id}
                                            data-testid={`revision-row-${rev.id}`}
                                            className={`flex flex-col gap-2 rounded-md border p-3 text-sm transition-colors ${
                                                isSelected
                                                    ? "border-primary bg-background shadow-xs"
                                                    : "border-border-soft bg-background/50 hover:bg-background"
                                            }`}
                                        >
                                            <div className="flex flex-wrap items-center justify-between gap-1.5">
                                                <span className="font-mono text-xs text-muted-foreground">
                                                    {formatDateTime(rev.created_at)}
                                                </span>
                                                <div className="flex flex-wrap items-center gap-1">
                                                    {isCurrent && (
                                                        <Badge
                                                            variant="solid"
                                                            tone="neutral"
                                                            data-testid="current-summary-badge"
                                                            className="text-[10px] px-1.5 py-0"
                                                        >
                                                            Current
                                                        </Badge>
                                                    )}
                                                    <Badge
                                                        variant="outline"
                                                        data-testid={`revision-role-${rev.id}`}
                                                        className="text-[10px] px-1.5 py-0 capitalize"
                                                    >
                                                        {rev.publication_role}
                                                    </Badge>
                                                    <Badge
                                                        variant="outline"
                                                        data-testid={`revision-review-${rev.id}`}
                                                        className="text-[10px] px-1.5 py-0 capitalize"
                                                    >
                                                        {rev.review_state}
                                                    </Badge>
                                                    <Badge
                                                        variant="outline"
                                                        data-testid={`revision-snapshot-badge-${rev.id}`}
                                                        className="text-[10px] px-1.5 py-0"
                                                    >
                                                        {rev.news_source_snapshot_id || rev.has_snapshot
                                                            ? "Evidence snapshot"
                                                            : "Legacy (no snapshot)"}
                                                    </Badge>
                                                </div>
                                            </div>

                                            <div className="flex flex-wrap items-center gap-1.5">
                                                <span
                                                    data-testid={`revision-origin-${rev.id}`}
                                                    className="font-medium text-foreground"
                                                >
                                                    {originLabel(rev.origin)}
                                                </span>
                                                <span className="text-muted-foreground">•</span>
                                                <span
                                                    data-testid={
                                                        prov.isKnown
                                                            ? `revision-provenance-${rev.id}`
                                                            : "revision-unknown-provenance"
                                                    }
                                                    className={`text-xs ${
                                                        prov.isKnown ? "text-muted-foreground" : "italic text-warning"
                                                    }`}
                                                >
                                                    {prov.text}
                                                </span>
                                            </div>

                                            <div className="flex items-center justify-between gap-2 pt-1 border-t border-border-soft/50">
                                                <Button
                                                    type="button"
                                                    variant="ghost"
                                                    size="sm"
                                                    onClick={() => setSelectedRevisionId(isSelected ? null : rev.id)}
                                                    data-testid={`btn-inspect-revision-${rev.id}`}
                                                    className="h-7 px-2 text-xs"
                                                >
                                                    {isSelected ? "Hide preview" : "Inspect text"}
                                                </Button>

                                                {rev.publication_role === "draft" ? (
                                                    <Button
                                                        type="button"
                                                        variant="outline"
                                                        size="sm"
                                                        onClick={() => handleReviewDraft(rev)}
                                                        data-testid={`btn-review-draft-${rev.id}`}
                                                        className="h-7 px-2 text-xs"
                                                        title="Review draft in editor"
                                                    >
                                                        Review draft in editor
                                                    </Button>
                                                ) : (
                                                    <Button
                                                        type="button"
                                                        variant="outline"
                                                        size="sm"
                                                        disabled={isCurrent}
                                                        onClick={() => setRestoreTarget(rev)}
                                                        data-testid={`btn-restore-revision-${rev.id}`}
                                                        className="h-7 px-2 text-xs"
                                                        title={
                                                            isCurrent
                                                                ? "This version is already the published summary"
                                                                : "Restore this version as the published summary"
                                                        }
                                                    >
                                                        <RotateCcw className="mr-1 size-3" />
                                                        Restore
                                                    </Button>
                                                )}
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>

                            <div
                                data-testid="revision-preview-pane"
                                className="flex flex-col gap-2 rounded-md border border-border-soft bg-background p-3 min-h-64"
                            >
                                <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                                    {selectedRevision
                                        ? `Historical preview: ${formatDateTime(selectedRevision.created_at)}`
                                        : "Current published summary"}
                                </span>

                                <div className="flex-1 overflow-y-auto rounded-sm border border-border-soft/60 bg-muted/20 p-3 font-mono text-xs whitespace-pre-wrap select-text">
                                    {selectedRevision
                                        ? selectedRevision.summary_markdown
                                        : currentSummary || "(No published summary)"}
                                </div>

                                {selectedRevision && (
                                    <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-soft">
                                        {selectedRevision.publication_role === "draft" ? (
                                            <Button
                                                type="button"
                                                variant="default"
                                                size="sm"
                                                onClick={() => handleReviewDraft(selectedRevision)}
                                                data-testid="btn-review-selected-draft"
                                                className="text-xs"
                                            >
                                                Review draft in editor
                                            </Button>
                                        ) : (
                                            <Button
                                                type="button"
                                                variant="default"
                                                size="sm"
                                                disabled={selectedRevision.summary_markdown === currentSummary}
                                                onClick={() => setRestoreTarget(selectedRevision)}
                                                data-testid="btn-restore-selected-revision"
                                                className="text-xs"
                                            >
                                                <RotateCcw className="mr-1 size-3" />
                                                Restore this version
                                            </Button>
                                        )}
                                    </div>
                                )}
                            </div>
                        </div>
                    )}
                </div>
            )}

            <Dialog open={!!restoreTarget} onOpenChange={(open) => !open && !isRestoring && setRestoreTarget(null)}>
                <DialogContent
                    data-testid="restore-confirm-dialog"
                    className="w-[calc(100vw-2rem)] max-w-md p-4 sm:p-6"
                >
                    <DialogHeader>
                        <DialogTitle>
                            {restoreTarget && (restoreTarget.news_source_snapshot_id || restoreTarget.has_snapshot)
                                ? "Restore summary revision?"
                                : "Restore legacy revision as review draft?"}
                        </DialogTitle>
                        <DialogDescription>
                            {restoreTarget &&
                                (restoreTarget.news_source_snapshot_id || restoreTarget.has_snapshot ? (
                                    <>
                                        This will restore the published summary to the version recorded on{" "}
                                        <span className="font-semibold text-foreground">
                                            {formatDateTime(restoreTarget.created_at)}
                                        </span>
                                        . The current published summary will be retained in revision history.
                                    </>
                                ) : (
                                    <>
                                        This historical revision has no evidence snapshot. Restoring it will create a
                                        review draft. You will need to review evidence and declare news usage before
                                        publishing.
                                    </>
                                ))}
                        </DialogDescription>
                    </DialogHeader>

                    {restoreTarget && (
                        <div className="rounded-md border border-border-soft bg-muted/30 p-2.5 text-xs text-muted-foreground flex flex-col gap-1">
                            <div>
                                <span className="font-medium text-foreground">Origin:</span>{" "}
                                {originLabel(restoreTarget.origin)}
                            </div>
                            <div>
                                <span className="font-medium text-foreground">Provenance:</span>{" "}
                                {provenanceLabel(restoreTarget).text}
                            </div>
                            <div>
                                <span className="font-medium text-foreground">Review state:</span>{" "}
                                {restoreTarget.review_state}
                            </div>
                        </div>
                    )}

                    <DialogFooter className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                        <Button
                            type="button"
                            variant="outline"
                            disabled={isRestoring}
                            onClick={() => setRestoreTarget(null)}
                            data-testid="btn-restore-cancel"
                        >
                            Cancel
                        </Button>
                        <Button
                            type="button"
                            variant="default"
                            disabled={isRestoring}
                            onClick={handleConfirmRestore}
                            data-testid="btn-restore-confirm"
                        >
                            {isRestoring ? (
                                <>
                                    <Loader2 className="mr-1.5 size-3.5 animate-spin" />
                                    Restoring…
                                </>
                            ) : restoreTarget &&
                              (restoreTarget.news_source_snapshot_id || restoreTarget.has_snapshot) ? (
                                "Restore summary"
                            ) : (
                                "Restore as review draft"
                            )}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </div>
    );
};

export default BillSummaryRevisionHistory;
